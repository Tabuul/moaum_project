package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
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
 * Deferment (V259, revised by V264), end to end: the student cannot open the form before the application fee is
 * confirmed; paid, the form opens and the request goes to the Bursary (the last school-fee payment read from the finance
 * record), the Head of Department, the faculty, the Academic Office (which cannot download it before the faculty's
 * approval and forwards it to the DVC in a numbered batch) and the DVC, whose decision carries a comment and is the
 * final approval, applying the academic effect: the
 * registered course of the period is DEFERRED (not failed, not in the GPA), the programme timeline grows by one
 * semester, the entry session and matriculation number stand; the return is listed and confirmed and the deferred
 * course is due on the next form under its own name. A stage cannot be skipped; another student, another department's
 * Head and a lecturer are refused; a rejected request extends nothing; a correction goes back to the desk that
 * returned it; the fee is the Bursary's to state. Needs DATABASE_URL.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT, properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@SuppressWarnings({"rawtypes", "unchecked"})
class DefermentIT {

    static final String SESSION = "2095/2096";
    static final String NEXT = "2096/2097";
    static final String TINY_PDF = "%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    String registrar, bursar, academic, dvc, hodMtc, hodEco, deanSc;

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2095);
        it.session(NEXT, 2096);
        // the first semester of the test session has begun, so an approved deferment of it comes into force at once
        it.db(() -> jdbc.sql("""
                INSERT INTO policy.semester (id, session, number, lectures_from, state)
                SELECT gen_random_uuid(), :s, 1, current_date - 1, 'OPEN' WHERE NOT EXISTS (SELECT 1 FROM policy.semester WHERE session = :s AND number = 1)
                """).param("s", SESSION).update());
        registrar = TestTokens.token(it.person("ZZDF-REG", "ZZDFREGISTRAR"), List.of("registrar"));
        bursar = TestTokens.token(it.person("ZZDF-BUR", "ZZDFBURSAR"), List.of("bursar"));
        academic = TestTokens.token(it.person("ZZDF-ACA", "ZZDFACADEMIC"), List.of("academic"));
        dvc = TestTokens.token(it.person("ZZDF-DVC", "ZZDFDVC"), List.of("dvc"));
        hodMtc = TestTokens.token(head("ZZDF-HOD-MTC", "MTC"), List.of("hod"));
        hodEco = TestTokens.token(head("ZZDF-HOD-ECO", "ECO"), List.of("hod"));
        UUID dean = it.person("ZZDF-DEAN", "ZZDFDEAN");
        grant(dean, "dean", "faculty", "SC");
        deanSc = TestTokens.token(dean, List.of("dean"));
        // the fee as the Bursary states it by default
        it.db(() -> jdbc.sql("UPDATE people.deferment_setting SET fee = 10000 WHERE id = 1").update());
    }

    private UUID head(String staffNo, String dept) {
        UUID p = it.person(staffNo, "ZZDFHEAD" + dept);
        grant(p, "hod", "department", dept);
        return p;
    }

    private void grant(UUID person, String office, String scopeKind, String scopeId) {
        it.db(() -> jdbc.sql("""
                INSERT INTO iam.office_assignment (id, person_id, office_code, scope_kind, scope_id, instrument, granted_by, valid_from)
                SELECT gen_random_uuid(), :p, :o, :k, :sid, 'integration test', :p, current_date
                 WHERE NOT EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = :p AND a.office_code = :o AND a.valid_to IS NULL)
                """).param("p", person).param("o", office).param("k", scopeKind).param("sid", scopeId).update());
    }

    /** a student of Computer Science at 200 level with an email and phone, entered in the test session */
    private UUID student(String tag, int n) {
        UUID s = it.student("ZZDF" + n + tag, "C00023", "MOAUM/ADM/95/" + (100000 + n), "MOAUM/MTC/95/" + n, 200);
        it.db(() -> {
            jdbc.sql("UPDATE people.student SET entry_session = '2094/2095', entry_level = 100 WHERE id = :s").param("s", s).update();
            return jdbc.sql("""
                INSERT INTO people.student_contact (student_id, phone, email, updated_at) VALUES (:s, '08011112222', 'zzdf' || :n || '@example.com', now())
                ON CONFLICT (student_id) DO UPDATE SET email = EXCLUDED.email, phone = EXCLUDED.phone
                """).param("s", s).param("n", s.toString().substring(0, 8)).update();
        });
        return s;
    }

    /** the student's registration for the period, with one course on it, approved */
    private UUID registered(UUID student, String session, int semester) {
        return it.db(() -> {
            jdbc.sql("INSERT INTO catalogue.course (code, title, units, semester, level, dept_code, state) VALUES ('ZZD 101', 'A course for the deferment test', 3, 1, 200, 'MTC', 'LIVE') ON CONFLICT (code) DO NOTHING").update();
            UUID offering = jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZD 101', :sess, :sem) ON CONFLICT (course_code, session, semester) DO UPDATE SET semester = EXCLUDED.semester RETURNING id")
                    .param("sess", session).param("sem", semester).query(UUID.class).single();
            UUID reg = jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), :s, :sess, :sem, 200, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED' RETURNING id")
                    .param("s", student).param("sess", session).param("sem", semester).query(UUID.class).single();
            jdbc.sql("INSERT INTO registration.entry (registration_id, offering_id, units, status) VALUES (:r, :o, 3, 'APPROVED') ON CONFLICT (registration_id, offering_id) DO NOTHING").param("r", reg).param("o", offering).update();
            return reg;
        });
    }

    /** a school-fee payment on the record, confirmed, so the Bursary has something to verify */
    private String schoolFeesPaid(UUID student, String session, int amount) {
        return it.db(() -> {
            String ref = jdbc.sql("SELECT finance.new_purpose_reference(:s, :ses, :a, 'School fees ' || :ses)").param("s", student).param("ses", session).param("a", amount).query(String.class).single();
            jdbc.sql("SELECT finance.confirm_payment(:r, 'BANK_BRANCH', 'teller for the test')").param("r", ref).query(String.class).single();
            return ref;
        });
    }

    /** the fee reference generated on the student's screen and confirmed like any other payment */
    private Map<String, Object> feePaid(String me) {
        ResponseEntity<Map> fee = it.call(me, HttpMethod.POST, "/api/v1/me/deferments/fee", null);
        assertThat(fee.getStatusCode().value()).as(String.valueOf(fee.getBody())).isEqualTo(200);
        assertThat(fee.getBody().get("state")).isEqualTo("PENDING");
        String ref = String.valueOf(fee.getBody().get("reference"));
        it.db(() -> jdbc.sql("SELECT finance.confirm_payment(:r, 'CARD', 'gateway for the test')").param("r", ref).query(String.class).single());
        return fee.getBody();
    }

    private Map<String, Object> opened(String me, String kind, Integer semester, String reason, String words) {
        ResponseEntity<Map> r = it.call(me, HttpMethod.POST, "/api/v1/me/deferments", semester == null
                ? Map.of("kind", kind, "session", SESSION, "reason", reason, "explanation", words, "declared", true)
                : Map.of("kind", kind, "session", SESSION, "semester", semester, "reason", reason, "explanation", words, "declared", true));
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    private String act(String token, UUID id, String action, String note) {
        Map<String, Object> body = note == null ? Map.of("action", action) : Map.of("action", action, "note", note);
        ResponseEntity<Map> r = it.call(token, HttpMethod.POST, "/api/v1/deferments/" + id + "/action", body);
        assertThat(r.getStatusCode().value()).as(action + ": " + r.getBody()).isEqualTo(200);
        return String.valueOf(r.getBody().get("state"));
    }

    private int refused(String token, UUID id, String action, String note) {
        Map<String, Object> body = note == null ? Map.of("action", action) : Map.of("action", action, "note", note);
        return it.call(token, HttpMethod.POST, "/api/v1/deferments/" + id + "/action", body).getStatusCode().value();
    }

    @Test
    void theFeeTheSixDesksAndTheAcademicEffect() {
        int n = new Random().nextInt(8000) + 1000;
        UUID student = student("A", n);
        UUID other = student("B", n + 1);
        String me = TestTokens.token(student, List.of("student"));
        String stranger = TestTokens.token(other, List.of("student"));
        registered(student, SESSION, 1);
        String feeRef = schoolFeesPaid(student, SESSION, 85000);

        // ── PAYMENT: the form is closed until the application fee is confirmed ──
        ResponseEntity<Map> home = it.get(me, "/api/v1/me/deferments");
        assertThat(home.getStatusCode().value()).isEqualTo(200);
        assertThat(((Map<String, Object>) home.getBody().get("eligibility")).get("eligible")).isEqualTo(true);
        assertThat(((Number) ((Map<String, Object>) home.getBody().get("setting")).get("fee")).intValue()).isEqualTo(10000);
        ResponseEntity<Map> closed = it.call(me, HttpMethod.POST, "/api/v1/me/deferments", Map.of("kind", "SEMESTER", "session", SESSION, "semester", 1, "reason", "PERSONAL", "explanation", "I must attend to a family matter away from Makurdi for the semester.", "declared", true));
        assertThat(closed.getStatusCode().value()).as("no fee, no form").isEqualTo(422);
        Map<String, Object> fee = feePaid(me);
        assertThat(((Number) fee.get("amount")).intValue()).isEqualTo(10000);
        Map<String, Object> feeNow = (Map<String, Object>) it.get(me, "/api/v1/me/deferments").getBody().get("fee");
        assertThat(feeNow.get("state")).isEqualTo("CONFIRMED");
        assertThat(feeNow.get("receipt_no")).isNotNull();

        // ── the form opens; a document is attached; the request is submitted to the Bursary ──
        Map<String, Object> d = opened(me, "SEMESTER", 1, "PERSONAL", "I must attend to a family matter away from Makurdi for the semester.");
        UUID id = UUID.fromString(String.valueOf(d.get("id")));
        assertThat(String.valueOf(d.get("reference"))).matches("DEF-\\d{4}-\\d{5}");
        assertThat(d.get("fee_state")).isEqualTo("CONFIRMED");
        assertThat(d.get("return_session")).isEqualTo(SESSION);
        assertThat(d.get("return_semester")).isEqualTo(2);
        ResponseEntity<Map> doc = it.call(me, HttpMethod.POST, "/api/v1/me/deferments/" + id + "/documents", Map.of("kind", "OTHER", "filename", "letter.pdf", "contentType", "application/pdf",
                "contentBase64", Base64.getEncoder().encodeToString(TINY_PDF.getBytes(StandardCharsets.US_ASCII))));
        assertThat(doc.getStatusCode().value()).as(String.valueOf(doc.getBody())).isEqualTo(200);
        String docId = String.valueOf(((List<Map<String, Object>>) doc.getBody().get("documents")).get(0).get("id"));
        ResponseEntity<Map> submitted = it.call(me, HttpMethod.POST, "/api/v1/me/deferments/" + id + "/submit", null);
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(submitted.getBody().get("state")).isEqualTo("SUBMITTED");
        assertThat(submitted.getBody().get("stage_label")).isEqualTo("WAITING BURSARY ACTION");
        // the fee is spent: a second form does not open on it
        assertThat(it.call(me, HttpMethod.POST, "/api/v1/me/deferments", Map.of("kind", "SESSION", "session", SESSION, "reason", "MEDICAL", "declared", true)).getStatusCode().value()).isEqualTo(422);

        // ── SECURITY: nobody skips a stage or reaches another's request ──
        assertThat(it.get(stranger, "/api/v1/me/deferments/" + id).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(stranger, "/api/v1/me/deferments/" + id + "/documents/" + docId + "/content").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(hodEco, "/api/v1/deferments/" + id).getStatusCode().value()).isEqualTo(403);
        assertThat(refused(ItSupport.token("lecturer"), id, "BURSARY_APPROVE", null)).isEqualTo(403);
        assertThat(refused(hodMtc, id, "RECOMMEND", null)).as("the HOD before the Bursary").isEqualTo(422);
        assertThat(refused(registrar, id, "APPROVE", null)).as("no stage is skipped").isEqualTo(422);
        assertThat(refused(dvc, id, "DVC_APPROVE", "too early")).isEqualTo(422);
        // the office is checked in the database as well as at the door
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("SELECT people.deferment_decide(:id, 'BURSARY_APPROVE', NULL, NULL, 'hod')").param("id", id).query(String.class).single()))
                .hasMessageContaining("Bursary");

        // ── BURSARY: the last school-fee payment is read, never typed; approval records it ──
        ResponseEntity<Map> atBursary = it.get(bursar, "/api/v1/deferments/" + id);
        assertThat(atBursary.getStatusCode().value()).as(String.valueOf(atBursary.getBody())).isEqualTo(200);
        Map<String, Object> fin = (Map<String, Object>) atBursary.getBody().get("financials");
        assertThat(fin.get("last_fee_ref")).isEqualTo(feeRef);
        assertThat(((Number) fin.get("last_fee_amount")).intValue()).isEqualTo(85000);
        assertThat(((Map<String, Object>) atBursary.getBody().get("may")).get("bursaryApprove")).isEqualTo(true);
        assertThat(refused(bursar, id, "REJECT", null)).as("a rejection carries its reason").isEqualTo(422);
        assertThat(act(bursar, id, "BURSARY_APPROVE", "Financial record in order")).isEqualTo("BURSARY_APPROVED");
        Map<String, Object> afterBursary = it.get(registrar, "/api/v1/deferments/" + id).getBody();
        assertThat(afterBursary.get("bursary_last_fee_ref")).isEqualTo(feeRef);
        assertThat(afterBursary.get("bursary_at")).isNotNull();
        assertThat(afterBursary.get("stage_label")).isEqualTo("WAITING HOD ACTION");
        assertThat(refused(bursar, id, "BURSARY_APPROVE", null)).as("no duplicate approval").isEqualTo(422);

        // ── ACADEMIC OFFICE sees every stage, but downloads only what the faculty has approved ──
        assertThat(it.get(academic, "/api/v1/deferments/" + id).getStatusCode().value()).isEqualTo(200);
        assertThat(it.get(academic, "/api/v1/deferments/" + id + "/application").getStatusCode().value()).as("not yet faculty-approved").isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/deferments/forward", Map.of()).getStatusCode().value()).as("nothing to forward yet").isEqualTo(422);

        // ── HOD then FACULTY, each at its own stage and within its own bound ──
        assertThat(it.get(hodEco, "/api/v1/deferments/" + id).getStatusCode().value()).isEqualTo(403);
        assertThat(refused(deanSc, id, "FAC_RECOMMEND", null)).as("the faculty before the department").isEqualTo(422);
        assertThat(act(hodMtc, id, "RECOMMEND", "Genuine")).isEqualTo("DEPT_RECOMMENDED");
        assertThat(act(deanSc, id, "FAC_RECOMMEND", null)).isEqualTo("FAC_RECOMMENDED");
        Map<String, Object> facApproved = it.get(academic, "/api/v1/deferments/" + id).getBody();
        assertThat(facApproved.get("stage_label")).isEqualTo("WAITING ACADEMIC OFFICE ACTION");
        assertThat(facApproved.get("downloadable")).isEqualTo(true);
        assertThat(it.get(academic, "/api/v1/deferments/" + id + "/application").getStatusCode().value()).isEqualTo(200);
        // the Academic Office does not approve on behalf of the desks
        assertThat(refused(academic, id, "DVC_APPROVE", "no")).isEqualTo(422);

        // ── FORWARDED TO DVC in a numbered batch ──
        ResponseEntity<Map> batch = it.call(academic, HttpMethod.POST, "/api/v1/deferments/forward", Map.of("note", "Forwarded for the semester's sitting"));
        assertThat(batch.getStatusCode().value()).as(String.valueOf(batch.getBody())).isEqualTo(200);
        assertThat(String.valueOf(batch.getBody().get("reference"))).matches("DEF-DVC-\\d{4}-\\d{5}");
        assertThat(((Number) batch.getBody().get("count")).intValue()).isGreaterThanOrEqualTo(1);
        Map<String, Object> forwarded = it.get(dvc, "/api/v1/deferments/" + id).getBody();
        assertThat(forwarded.get("state")).isEqualTo("FORWARDED_TO_DVC");
        assertThat(forwarded.get("batch_reference")).isEqualTo(batch.getBody().get("reference"));
        assertThat(it.call(academic, HttpMethod.POST, "/api/v1/deferments/forward", Map.of()).getStatusCode().value()).as("not forwarded twice").isEqualTo(422);
        // the DVC searches by batch and by name, and opens the document in the viewer (the same authorised door)
        List<Map<String, Object>> byBatch = (List<Map<String, Object>>) it.get(dvc, "/api/v1/deferments?batch=" + batch.getBody().get("reference")).getBody().get("rows");
        assertThat(byBatch.stream().map(r -> String.valueOf(r.get("id")))).contains(id.toString());
        assertThat(((List<Map<String, Object>>) it.get(dvc, "/api/v1/deferments?q=ZZDF" + n + "A").getBody().get("rows")).stream().map(r -> String.valueOf(r.get("id")))).contains(id.toString());
        ResponseEntity<byte[]> viewed = it.getBytes(dvc, "/api/v1/deferments/" + id + "/documents/" + docId + "/content");
        assertThat(viewed.getStatusCode().value()).isEqualTo(200);
        assertThat(new String(viewed.getBody(), StandardCharsets.US_ASCII)).startsWith("%PDF");

        // ── DVC: a comment is required; the approval is final and applies the academic effect, transactionally ──
        assertThat(refused(dvc, id, "DVC_APPROVE", null)).as("the DVC's decision carries a comment").isEqualTo(422);
        BigDecimal cgpaBefore = jdbc.sql("SELECT cgpa FROM assessment.student_gpa(:s) ORDER BY session DESC, semester DESC LIMIT 1").param("s", student).query(BigDecimal.class).optional().orElse(null);
        String entryBefore = jdbc.sql("SELECT entry_session FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        String matricBefore = jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single();
        Map<String, Object> tlBefore = jdbc.sql("SELECT * FROM people.programme_timeline(:s)").param("s", student).query().singleRow();
        assertThat(act(dvc, id, "DVC_APPROVE", "Recommended; the reason is genuine and the record is clean")).isEqualTo("ACTIVE");
        Map<String, Object> approved = it.get(registrar, "/api/v1/deferments/" + id).getBody();
        assertThat(approved.get("dvc_note")).isEqualTo("Recommended; the reason is genuine and the record is clean");
        assertThat(refused(registrar, id, "SBC_APPROVE", null)).as("no stage after the DVC").isEqualTo(422);
        Map<String, Object> effect = (Map<String, Object>) approved.get("effect");
        assertThat(effect.get("applied")).isEqualTo(true);
        assertThat(((Number) effect.get("extension_semesters")).intValue()).isEqualTo(1);
        assertThat(((Number) effect.get("courses_affected")).intValue()).isEqualTo(1);
        // the registered course of the period is DEFERRED: not failed, not in the results, not in the GPA
        assertThat(jdbc.sql("SELECT e.status FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id WHERE r.student_id = :s AND r.session = :ses AND r.semester = 1").param("s", student).param("ses", SESSION).query(String.class).single()).isEqualTo("DEFERRED");
        assertThat(jdbc.sql("SELECT count(*) FROM assessment.student_results(:s) WHERE course_code = 'ZZD 101'").param("s", student).query(Long.class).single()).isEqualTo(0L);
        assertThat(jdbc.sql("SELECT count(*) FROM assessment.student_results(:s) WHERE grade = 'F' AND course_code = 'ZZD 101'").param("s", student).query(Long.class).single()).isEqualTo(0L);
        BigDecimal cgpaAfter = jdbc.sql("SELECT cgpa FROM assessment.student_gpa(:s) ORDER BY session DESC, semester DESC LIMIT 1").param("s", student).query(BigDecimal.class).optional().orElse(null);
        assertThat(cgpaAfter).isEqualTo(cgpaBefore);
        List<Map<String, Object>> deferredCourses = (List<Map<String, Object>>) approved.get("deferredCourses");
        assertThat(deferredCourses).hasSize(1);
        assertThat(deferredCourses.get(0).get("course_code")).isEqualTo("ZZD 101");
        assertThat(deferredCourses.get(0).get("status")).isEqualTo("DEFERRED");
        // the timeline: +1 semester, the original untouched, the entry session and the matriculation number unchanged
        Map<String, Object> tl = (Map<String, Object>) approved.get("timeline");
        assertThat(((Number) tl.get("original_semesters")).intValue()).isEqualTo(((Number) tlBefore.get("original_semesters")).intValue());
        assertThat(((Number) tl.get("approved_semesters")).intValue()).isEqualTo(((Number) tlBefore.get("approved_semesters")).intValue() + 1);
        assertThat(((Number) tl.get("adjusted_semesters")).intValue()).isEqualTo(((Number) tl.get("original_semesters")).intValue() + ((Number) tl.get("approved_semesters")).intValue());
        assertThat(jdbc.sql("SELECT entry_session FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo(entryBefore);
        assertThat(jdbc.sql("SELECT matric_no FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo(matricBefore);
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo("DEFERRED");
        // every act is on the trail, including the readings
        List<String> actions = jdbc.sql("SELECT action FROM people.deferment_event WHERE deferment_id = :id").param("id", id).query(String.class).list();
        assertThat(actions).contains("FEE_PAID", "SUBMITTED", "BURSARY_APPROVE", "RECOMMEND", "FAC_RECOMMEND", "FORWARD", "DVC_APPROVE", "EFFECT_APPLIED", "VIEWED", "DOCUMENT_VIEWED", "DOWNLOADED", "ACTIVATED");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'student' AND about_id = :s AND subject LIKE 'DEFERMENT APPROVED%'").param("s", student).query(Long.class).single()).isGreaterThanOrEqualTo(1);

        // ── the register refuses the deferred period, not the other semester ──
        // (the period's registration already exists, so the gate is met on a submission of it, not on a new draft)
        assertThatThrownBy(() -> it.db(() -> jdbc.sql("UPDATE registration.course_registration SET status = 'SUBMITTED', submitted_at = now() WHERE student_id = :s AND session = :ses AND semester = 1").param("s", student).param("ses", SESSION).update()))
                .hasMessageContaining("REGISTRATION UNAVAILABLE");
        it.db(() -> jdbc.sql("SELECT registration.student_draft(:s, :ses, 2)").param("s", student).param("ses", SESSION).query(UUID.class).single());

        // ── RESUMPTION: due to return, listed with the deferred course; the return confirmed; the course due on the next form under its own name ──
        it.db(() -> jdbc.sql("UPDATE people.deferment SET return_on = current_date WHERE id = :id").param("id", id).update());
        List<Map<String, Object>> due = (List<Map<String, Object>>) it.get(hodMtc, "/api/v1/deferments/returns?status=DUE&q=ZZDF" + n + "A").getBody().get("rows");
        assertThat(due.stream().map(r -> String.valueOf(r.get("id")))).contains(id.toString());
        assertThat(((Number) due.stream().filter(r -> id.toString().equals(String.valueOf(r.get("id")))).findFirst().orElseThrow().get("deferred_due")).intValue()).isEqualTo(1);
        ResponseEntity<Map> back = it.call(hodMtc, HttpMethod.POST, "/api/v1/deferments/" + id + "/return", Map.of("note", "Presented at the department"));
        assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
        assertThat(back.getBody().get("state")).isEqualTo("COMPLETED");
        assertThat(jdbc.sql("SELECT status FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo("ACTIVE");
        it.db(() -> jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (gen_random_uuid(), 'ZZD 101', :sess, 1) ON CONFLICT (course_code, session, semester) DO NOTHING").param("sess", NEXT).update());
        Map<String, Object> menuRow = jdbc.sql("SELECT * FROM registration.student_menu(:s, :ses, 1) WHERE course_code = 'ZZD 101'").param("s", student).param("ses", NEXT).query().singleRow();
        assertThat(menuRow.get("deferred")).isEqualTo(true);
        assertThat(menuRow.get("basis")).isEqualTo("Deferred");
        assertThat(String.valueOf(menuRow.get("deferred_from"))).contains(SESSION);
        UUID nextReg = it.db(() -> jdbc.sql("SELECT registration.student_draft(:s, :ses, 1)").param("s", student).param("ses", NEXT).query(UUID.class).single());
        assertThat(jdbc.sql("SELECT entry_type FROM registration.entry e JOIN catalogue.offering o ON o.id = e.offering_id WHERE e.registration_id = :r AND o.course_code = 'ZZD 101'").param("r", nextReg).query(String.class).single()).isEqualTo("DEFERRED");
        assertThat(jdbc.sql("SELECT status FROM people.deferred_courses(:s) WHERE course_code = 'ZZD 101'").param("s", student).query(String.class).single()).isEqualTo("REGISTERED");

        // ── a REJECTED request extends nothing; a CORRECTION goes back to the desk that returned it ──
        feePaid(stranger);
        Map<String, Object> d2 = opened(stranger, "SESSION", null, "FINANCIAL", "I cannot raise the fees this session and will return next session.");
        UUID id2 = UUID.fromString(String.valueOf(d2.get("id")));
        assertThat(it.call(stranger, HttpMethod.POST, "/api/v1/me/deferments/" + id2 + "/submit", null).getBody().get("state")).isEqualTo("SUBMITTED");
        assertThat(act(bursar, id2, "CORRECTION", "Attach the evidence of your circumstances")).isEqualTo("CORRECTION_REQUIRED");
        assertThat(it.call(stranger, HttpMethod.POST, "/api/v1/me/deferments/" + id2 + "/submit", null).getBody().get("state")).as("back to the Bursary").isEqualTo("SUBMITTED");
        assertThat(act(bursar, id2, "BURSARY_APPROVE", null)).isEqualTo("BURSARY_APPROVED");
        assertThat(act(hodMtc, id2, "CORRECTION", "Name the semester you intend to return")).isEqualTo("CORRECTION_REQUIRED");
        assertThat(it.call(stranger, HttpMethod.POST, "/api/v1/me/deferments/" + id2 + "/submit", null).getBody().get("state")).as("back to the HOD, not the Bursary").isEqualTo("BURSARY_APPROVED");
        assertThat(act(hodMtc, id2, "REJECT", "The department does not support a whole-session deferment on these grounds")).isEqualTo("REJECTED");
        Map<String, Object> tl2 = jdbc.sql("SELECT * FROM people.programme_timeline(:s)").param("s", other).query().singleRow();
        assertThat(((Number) tl2.get("approved_semesters")).intValue()).isEqualTo(0);
        assertThat(jdbc.sql("SELECT count(*) FROM people.deferred_course WHERE deferment_id = :id").param("id", id2).query(Long.class).single()).isEqualTo(0L);

        // ── the dashboards and the fee setting ──
        Map<String, Object> totals = (Map<String, Object>) it.get(bursar, "/api/v1/deferments/dashboard?session=" + SESSION).getBody().get("totals");
        assertThat(((Number) totals.get("approved")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) totals.get("rejected")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) ((Map<String, Object>) it.get(hodEco, "/api/v1/deferments/dashboard?session=" + SESSION).getBody().get("totals")).get("total")).intValue()).isEqualTo(0);
        assertThat(it.call(registrar, HttpMethod.PUT, "/api/v1/deferments/settings", Map.of("fee", 12000)).getStatusCode().value()).as("the fee is the Bursary's").isEqualTo(422);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/deferments/settings", Map.of("fee", 12000)).getStatusCode().value()).isEqualTo(200);
        assertThat(((Number) ((Map<String, Object>) it.get(bursar, "/api/v1/deferments/settings").getBody()).get("fee")).intValue()).isEqualTo(12000);
        assertThat(it.call(bursar, HttpMethod.PUT, "/api/v1/deferments/settings", Map.of("fee", 10000)).getStatusCode().value()).isEqualTo(200);
    }
}
