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

    /** V501: the session's school fees stated for the test (an examination card is the card of a student who paid), taken away after it */
    @org.junit.jupiter.api.AfterEach
    void clean() {
        new ItSupport(port, jdbc, transactions).db(() -> jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s AND item = 'School fees (check codes)'")
                .param("s", SESSION).update());
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
            // an earlier run on the same database left its examination session (cards released before the cut-over): the old code would be honoured before this run releases any
            jdbc.sql("DELETE FROM assessment.exam_session WHERE session = :ses AND NOT EXISTS (SELECT 1 FROM assessment.score_sheet sh WHERE sh.exam_session_id = assessment.exam_session.id)").param("ses", SESSION).update();
            // V501: the fees the payment below clears, stated, so the student's examination card is the card of a student who paid
            jdbc.sql("INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code) VALUES (:ses, 'School fees (check codes)', 1000, 100, 'C00023')")
                    .param("ses", SESSION).update();
            jdbc.sql("""
                    INSERT INTO finance.payment_reference (id, student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (gen_random_uuid(), :s, :ses, :r, 'School fees (full session)', 1000, now() + interval '30 days', now(), :s, 'BANK', :rc)
                    """).param("s", student).param("ses", SESSION).param("r", reference).param("rc", receiptNo).update();
            UUID reg = jdbc.sql("""
                    INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, submitted_at, approved_at)
                    VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'APPROVED', now(), now()) RETURNING id
                    """).param("s", student).param("ses", SESSION).query(UUID.class).single();
            // V501: an examination card is the card of a registration carrying a course
            jdbc.sql("""
                    INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, kind, state)
                    SELECT 'CKC 179', 'Check Code Course', 3, 1, 100, p.dept_code, 'Core', 'LIVE' FROM ref.programme p WHERE p.code = 'C00023'
                    ON CONFLICT (code) DO NOTHING
                    """).update();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'CKC 179', :ses, 1) ON CONFLICT (course_code, session, semester, stream) DO NOTHING")
                    .param("ses", SESSION).update();
            return jdbc.sql("""
                    INSERT INTO registration.entry (registration_id, offering_id, units, entry_type, status)
                    SELECT :r, o.id, 3, 'CURRENT', 'APPROVED' FROM catalogue.offering o WHERE o.course_code = 'CKC 179' AND o.session = :ses AND o.semester = 1 AND o.stream = 'REGULAR'
                    """).param("r", reg).param("ses", SESSION).update();
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

    /** the receipt of an applicant's Post-UTME application fee: the code comes with the receipt, the same verification page
     *  answers it with the applicant's name, application number and the fee; another code, or the code on another reference, says nothing */
    @Test
    void anApplicantsFeeReceiptCarriesASignedCodeTheVerifierAnswers() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2079);
        int n = new java.util.Random().nextInt(90_000_000) + 10_000_000;
        String jamb = "2179" + n + "SC";
        String tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        String reference = "MOAUM-APP-ZZ" + tag;
        String unpaid = "MOAUM-APP-ZY" + tag;
        String applicationNo = "APP/79/" + String.format("%06d", n % 1_000_000);
        UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), app = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) VALUES (:id, :s, :j, :sn, 'Receipt Person', (SELECT name FROM ref.programme WHERE code = 'C00023'), 'UTME', 100, 'PROPOSED')")
                    .param("id", cand).param("s", SESSION).param("j", jamb).param("sn", "ZZRECEIPT-" + tag).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at) VALUES (:id, :a, :c, :s, :no, now())")
                    .param("id", app).param("a", acct).param("c", cand).param("s", SESSION).param("no", applicationNo).update();
            jdbc.sql("""
                    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                    VALUES (gen_random_uuid(), :a, 'APPLICATION', :r, 2000, now() + interval '7 days', now(), :acc, 'Old-portal migration', :rc)
                    """).param("a", app).param("r", reference).param("acc", acct).param("rc", "RCT-ZZ-" + tag).update();
            return jdbc.sql("""
                    INSERT INTO admissions.fee_reference (id, application_id, kind, reference, amount, expires_at)
                    VALUES (gen_random_uuid(), :a, 'APPLICATION', :r, 2000, now() + interval '7 days')
                    """).param("a", app).param("r", unpaid).update();
        });
        String me = TestTokens.token(acct, List.of("applicant"));

        Map<String, Object> receipt = it.get(me, "/api/v1/applicant/me/receipts/" + reference).getBody();
        String code = String.valueOf(receipt.get("check_code"));
        assertThat(code).matches("[0-9A-F]{12}");
        assertThat(receipt).containsEntry("kind", "APPLICATION").containsEntry("route", "UTME");
        Map<String, Object> v = it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=" + code, null).getBody();
        assertThat(v).containsEntry("genuine", true).containsEntry("holder", "APPLICANT").containsEntry("feeKind", "APPLICATION")
                .containsEntry("applicationNo", applicationNo).doesNotContainKey("legacy");
        assertThat(String.valueOf(v.get("name"))).startsWith("ZZRECEIPT-" + tag);
        // the public page takes the reference or the receipt number with the code
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/RCT-ZZ-" + tag + "?c=" + code, null).getBody())
                .containsEntry("genuine", true).containsEntry("applicationNo", applicationNo).containsEntry("reference", reference);
        // a wrong code, or this receipt's code on another reference, verifies nothing; an unconfirmed reference has no receipt
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=000000000000", null).getBody()).containsOnlyKeys("genuine").containsEntry("genuine", false);
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + unpaid + "?c=" + code, null).getBody()).containsOnlyKeys("genuine").containsEntry("genuine", false);
        assertThat(it.get(me, "/api/v1/applicant/me/receipts/" + unpaid).getStatusCode().value()).isEqualTo(404);
    }

    /** a postgraduate applicant's fee receipt: listed with the applicant's own receipts, signed the same way, answered by the same
     *  verification page with the programme and the postgraduate route; another applicant cannot read it */
    @Test
    void aPostgraduateApplicantsFeeReceiptIsListedSignedAndVerified() {
        ItSupport it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2079);
        String n = String.format("%06d", new java.util.Random().nextInt(900_000) + 100_000);
        String tag = UUID.randomUUID().toString().substring(0, 6).toUpperCase();
        String reference = "PGAPP-ZZ" + tag;
        String applicationNo = "PG/79/" + n;
        UUID applicant = UUID.randomUUID(), other = UUID.randomUUID(), app = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.pg_applicant (id, session, surname, other_names, email, phone, password_hash) VALUES (:id, :s, :sn, 'Receipt Person', :e, '08060000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", applicant).param("s", SESSION).param("sn", "ZZPGRECEIPT-" + tag).param("e", "pg-receipt-" + tag.toLowerCase() + "@example.test").update();
            jdbc.sql("INSERT INTO admissions.pg_applicant (id, session, surname, other_names, email, phone, password_hash) VALUES (:id, :s, 'ZZPGOTHER', 'Other Person', :e, '08060000001', crypt('x', gen_salt('bf', 12)))")
                    .param("id", other).param("s", SESSION).param("e", "pg-other-" + tag.toLowerCase() + "@example.test").update();
            jdbc.sql("INSERT INTO admissions.pg_application (id, applicant_id, session, application_no, programme_code, entry_level, state) VALUES (:id, :ap, :s, :no, 'C00023', 800, 'SUBMITTED')")
                    .param("id", app).param("ap", applicant).param("s", SESSION).param("no", applicationNo).update();
            return jdbc.sql("""
                    INSERT INTO admissions.pg_fee_reference (application_id, kind, reference, amount, expires_at, confirmed_at, channel)
                    VALUES (:a, 'APPLICATION', :r, 15000, now() + interval '7 days', now(), 'Card')
                    """).param("a", app).param("r", reference).update();
        });
        String me = TestTokens.token(applicant, List.of("applicant"));

        Map<String, Object> list = it.get(me, "/api/v1/pg/me/receipts").getBody();
        assertThat((List<Map<String, Object>>) list.get("rows")).extracting(r -> r.get("reference")).containsExactly(reference);
        Map<String, Object> receipt = it.get(me, "/api/v1/pg/me/receipts/" + reference).getBody();
        String code = String.valueOf(receipt.get("check_code"));
        assertThat(code).matches("[0-9A-F]{12}");
        assertThat(receipt).containsEntry("route", "POSTGRADUATE").containsEntry("kind", "APPLICATION").containsEntry("application_no", applicationNo);
        Map<String, Object> v = it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=" + code, null).getBody();
        assertThat(v).containsEntry("genuine", true).containsEntry("holder", "APPLICANT").containsEntry("route", "POSTGRADUATE")
                .containsEntry("feeKind", "APPLICATION").containsEntry("applicationNo", applicationNo).containsEntry("reference", reference);
        assertThat(String.valueOf(v.get("name"))).startsWith("ZZPGRECEIPT-" + tag);
        assertThat(it.anon(HttpMethod.GET, "/api/v1/verify/receipt/" + reference + "?c=000000000000", null).getBody()).containsOnlyKeys("genuine").containsEntry("genuine", false);
        // another applicant reads none of it
        String theirs = TestTokens.token(other, List.of("applicant"));
        assertThat(it.get(theirs, "/api/v1/pg/me/receipts/" + reference).getStatusCode().value()).isEqualTo(404);
        assertThat((List<?>) it.get(theirs, "/api/v1/pg/me/receipts").getBody().get("rows")).isEmpty();
    }
}
