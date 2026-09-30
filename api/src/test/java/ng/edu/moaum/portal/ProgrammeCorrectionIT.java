package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.math.BigDecimal;
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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * Programme Changes (V297), end to end: an applicant offered Computer Science, accepted, screened successful, on the register
 * and with school fees paid is found to have been admitted in error. The ordinary change is shut after the decision; the
 * correction is previewed (the road, the engine's verdict, the fees before and after), recommended by the Academic Office
 * with the error described, refused to the Academic Office's approval, approved by the Registrar — the candidate's and the
 * student's programme follow, the school fees paid are kept against the new programme's, the letter is reissued, the
 * applicant is told — and listed on the register with the programme applied for and the programme held now. A correction
 * recommended by the Registrar is not decided by the same officer; the Deputy Registrar rejects it with the reason. Before
 * the decision the ordinary change applies; after matriculation it is a transfer. The doors hold.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class ProgrammeCorrectionIT {

    static final String SESSION = "2115/2116";
    static final String PATH = "/api/v1/admissions/sessions/2115/2116";
    static final String CS = "C00023", ACC = "C00019";
    static final UUID POLICY = UUID.fromString("e1191b1e-0000-4000-8000-000000002115");

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String dregistrar = ItSupport.token("dregistrar");
    final String bursar = ItSupport.token("bursar");
    final String housing = ItSupport.token("housing");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2115);
        it.openChecking(SESSION);
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, state, instrument, in_force) VALUES (:id, :s, 1200, 70, 30, 'IN_FORCE', 'Senate minute CorrectionIT/1', tstzrange(now(), NULL)) ON CONFLICT DO NOTHING")
                    .param("id", POLICY).param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.load_cutoff (session, cutoff) VALUES (:s, 140) ON CONFLICT (session) DO UPDATE SET cutoff = 140").param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff) SELECT :id, code, 100, 150 FROM ref.faculty ON CONFLICT DO NOTHING").param("id", POLICY).update();
            for (String[] r : new String[][] {{CS, "200"}, {ACC, "180"}}) {
                jdbc.sql("INSERT INTO admissions.programme_rule (policy_id, programme_code, cutoff, quota, olevel_text, utme_text, de_text, olevel_credits, olevel_sittings) VALUES (:id, :c, :k, 50, 'Five credits (test)', 'As configured (test)', 'A-Level (test)', 5, 2) ON CONFLICT (policy_id, programme_code) DO NOTHING")
                        .param("id", POLICY).param("c", r[0]).param("k", Integer.parseInt(r[1])).update();
            }
            jdbc.sql("DELETE FROM admissions.rule_subject WHERE group_id IN (SELECT id FROM admissions.rule_subject_group WHERE policy_id = :id)").param("id", POLICY).update();
            jdbc.sql("DELETE FROM admissions.rule_subject_group WHERE policy_id = :id").param("id", POLICY).update();
            group(CS, "OLEVEL_REQUIRED", "C6", "Physics", "Chemistry");
            group(CS, "UTME", null, "Physics", "Chemistry/Biology");
            group(ACC, "OLEVEL_REQUIRED", "C6", "Economics/Accounting");
            group(ACC, "UTME", null, "Economics");
            jdbc.sql("INSERT INTO admissions.screening_policy (session) VALUES (:s) ON CONFLICT (session) DO UPDATE SET enabled = true").param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.applicant_fee (session, application_fee, portal_charge, acceptance_fee, checking_fee) VALUES (:s, 2000, 0, 25000, 3000) ON CONFLICT (session) DO UPDATE SET acceptance_fee = 25000, checking_fee = 3000").param("s", SESSION).update();
            // the session's school fees at 100 level: Computer Science 150,000, Accounting 120,000
            for (String[] f : new String[][] {{CS, "150000"}, {ACC, "120000"}}) {
                jdbc.sql("""
                        INSERT INTO finance.fee_schedule (session, item, amount, level, programme_code, ord)
                        SELECT :s, 'Tuition (correction IT)', :a, 100, :p, 1
                         WHERE NOT EXISTS (SELECT 1 FROM finance.fee_schedule x WHERE x.session = :s AND x.item = 'Tuition (correction IT)' AND x.programme_code = :p AND x.ended_at IS NULL)
                        """).param("s", SESSION).param("a", new BigDecimal(f[1])).param("p", f[0]).update();
            }
            return null;
        });
    }

    /** the session's fees and the payments made against them go with the test: another test reads the sessions that have charges */
    @AfterEach
    void tearDown() {
        it.db(() -> {
            jdbc.sql("DELETE FROM finance.payment_reference WHERE session = :s").param("s", SESSION).update();
            jdbc.sql("DELETE FROM finance.fee_schedule WHERE session = :s").param("s", SESSION).update();
            return null;
        });
    }

    void group(String programme, String scope, String minGrade, String... items) {
        UUID g = UUID.randomUUID();
        jdbc.sql("INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose, min_grade) VALUES (:g, :p, :c, :s, 1, :m)")
                .param("g", g).param("p", POLICY).param("c", programme).param("s", scope).param("m", minGrade, java.sql.Types.VARCHAR).update();
        for (String i : items) jdbc.sql("INSERT INTO admissions.rule_subject (group_id, subject) VALUES (:g, :s)").param("g", g).param("s", i).update();
    }

    record Applicant(UUID app, UUID account, UUID candidate, String jamb, String surname, String token) { }

    static Map<String, String> g(String s, String gr) { return Map.of("s", s, "g", gr); }
    /** qualified for Computer Science and for Accounting alike: Physics and Economics in the UTME, credits in both at O'Level */
    static final List<Map<String, String>> SCIENCE = List.of(g("English Language", "C6"), g("Mathematics", "B3"), g("Physics", "C5"), g("Chemistry", "C6"), g("Biology", "C4"), g("Economics", "B3"));
    static final List<String> UTME = List.of("English Language", "Mathematics", "Physics", "Economics");

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    /** an applicant offered a place and the offer released, on the CAPS list, O'Level as JAMB sent it */
    Applicant offered(String programme, int score) {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = "2115" + n + "PC";
        String surname = "ZZCORRECT-" + n;
        return it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), appId = UUID.randomUUID(), batch = UUID.randomUUID(), att = UUID.randomUUID(), sit = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) VALUES (:id, :s, :j, :sn, 'Test Person', (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, 'PROPOSED')")
                    .param("id", cand).param("s", SESSION).param("j", jamb).param("sn", surname).param("p", programme).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, score_released_at, decision, decision_basis, decided_at, decision_released_at) VALUES (:id, :a, :c, :s, :no, now(), now(), now(), 'OFFERED', 'NM', now(), now())")
                    .param("id", appId).param("a", acct).param("c", cand).param("s", SESSION).param("no", "APP/15/" + String.format("%06d", n % 1_000_000)).update();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'correct.xlsx', decode(md5(:id::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga) VALUES (gen_random_uuid(), :b, :s, :j, jsonb_build_object('Subject1', :s1, 'Subject2', :s2, 'Subject3', :s3, 'Subject4', :s4), :sn, 'Test Person', :p, :agg, 'UTME', 'F', 'Benue', 'Gboko')")
                    .param("b", batch).param("s", SESSION).param("j", jamb).param("s1", UTME.get(0)).param("s2", UTME.get(1)).param("s3", UTME.get(2)).param("s4", UTME.get(3)).param("sn", surname).param("p", programme).param("agg", score).update();
            jdbc.sql("UPDATE admissions.candidate SET offer_state = 'ADMITTED', admitted_from = (SELECT id FROM admissions.caps_row WHERE session = :s AND jamb_reg_no = :j) WHERE id = :c").param("s", SESSION).param("j", jamb).param("c", cand).update();
            jdbc.sql("INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at) VALUES (:id, :s, 'OLEVEL', :n, :k, 'EXACT', :c, now())")
                    .param("id", att).param("s", SESSION).param("n", jamb + "-olevel.json").param("k", jamb).param("c", cand).update();
            jdbc.sql("INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_year, exam_number, ord) VALUES (:id, :a, :s, :k, 'WAEC', '2114', :no, 1)")
                    .param("id", sit).param("a", att).param("s", SESSION).param("k", jamb).param("no", "WAEC/" + n).update();
            for (Map<String, String> x : SCIENCE) jdbc.sql("INSERT INTO admissions.olevel_grade (sitting_id, subject, grade) VALUES (:s, :j, :g)").param("s", sit).param("j", x.get("s")).param("g", x.get("g")).update();
            return new Applicant(appId, acct, cand, jamb, surname, TestTokens.token(acct, List.of("applicant")));
        });
    }

    /** the checking fee and the check (V271, V295), then the acceptance fee and the undertaking */
    void checkAndAccept(Applicant a) {
        String chk = String.valueOf(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "CHECKING")).getBody().get("reference"));
        assertThat(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + chk + "/confirm", Map.of("channel", "Card")).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/admission/checked", Map.of()).getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)).getStatusCode().value()).isEqualTo(200);
        String acc = String.valueOf(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getBody().get("reference"));
        ResponseEntity<Map> c = it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + acc + "/confirm", Map.of("channel", "Card"));
        assertThat(c.getStatusCode().value()).as(String.valueOf(c.getBody())).isEqualTo(200);
    }

    UUID studentOf(Applicant a) {
        return jdbc.sql("SELECT id FROM people.student WHERE candidate_id = :c").param("c", a.candidate()).query(UUID.class).single();
    }

    @Test
    void anAdmissionFoundInErrorIsCorrectedAfterSchoolFeesAndListed() {
        Applicant a = offered(CS, 210);
        checkAndAccept(a);
        Map<String, Object> letter1 = m(it.get(a.token(), "/api/v1/applicant/me/letter").getBody());
        assertThat(((Number) letter1.get("version")).intValue()).isEqualTo(1);
        // screened successful: on the register; the school fees of Computer Science paid in full
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/start", Map.of()).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> screened = it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/decide", Map.of("decision", "SUCCESSFUL", "remarks", "All originals sighted"));
        assertThat(screened.getStatusCode().value()).as(String.valueOf(screened.getBody())).isEqualTo(200);
        UUID student = studentOf(a);
        it.db(() -> jdbc.sql("""
                INSERT INTO finance.payment_reference (student_id, session, reference, purpose, amount, expires_at, confirmed_at, confirmed_by, channel, receipt_no)
                VALUES (:st, :s, :r, 'School fees 2115/2116', 150000, now() + interval '1 day', now(), gen_random_uuid(), 'Card', :rc)
                """).param("st", student).param("s", SESSION).param("r", "MOAUM-FEE-" + a.jamb()).param("rc", "RCPT-" + a.jamb()).update());

        // the ordinary change is shut once the decision is released and the screening successful
        ResponseEntity<Map> ordinary = it.call(academic, HttpMethod.POST, PATH + "/eligibility/" + a.app() + "/change", Map.of("programmeCode", ACC, "reasonCode", "ADMISSION_POLICY"));
        assertThat(ordinary.getStatusCode().value()).isEqualTo(422);

        // the preview: the road, the engine's verdict on Accounting, the fees before and after
        ResponseEntity<Map> preview = it.get(academic, PATH + "/programme-changes/" + a.app() + "/preview?to=" + ACC);
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        Map<String, Object> pv = preview.getBody();
        assertThat(pv.get("route")).isEqualTo("CORRECTION");
        assertThat(pv.get("stage")).isEqualTo("SCHOOL_FEES_PAID");
        assertThat(m(pv.get("target")).get("result")).isEqualTo("ELIGIBLE");
        assertThat(((Number) m(pv.get("fees")).get("dueNow")).intValue()).isEqualTo(150000);
        assertThat(((Number) m(pv.get("fees")).get("dueAfter")).intValue()).isEqualTo(120000);
        assertThat(((Number) m(pv.get("fees")).get("excessAfter")).intValue()).isEqualTo(30000);
        assertThat(pv.get("letterIssued")).isEqualTo(true);

        // recommended by the Academic Office with the error described; the bursary may not recommend
        ResponseEntity<Map> noNote = it.call(academic, HttpMethod.POST, PATH + "/programme-changes/" + a.app() + "/correct", Map.of("programmeCode", ACC, "reasonCode", "ADMISSION_ERROR"));
        assertThat(noNote.getStatusCode().value()).isEqualTo(422);
        assertThat(noNote.getBody().get("code")).isEqualTo("CORRECTION_NOTE_REQUIRED");
        assertThat(it.call(bursar, HttpMethod.POST, PATH + "/programme-changes/" + a.app() + "/correct", Map.of("programmeCode", ACC, "reasonCode", "ADMISSION_ERROR", "note", "x")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> rec = it.call(academic, HttpMethod.POST, PATH + "/programme-changes/" + a.app() + "/correct",
                Map.of("programmeCode", ACC, "reasonCode", "ADMISSION_ERROR", "note", "Offered Computer Science in error: the Board's approved list names Accounting"));
        assertThat(rec.getStatusCode().value()).as(String.valueOf(rec.getBody())).isEqualTo(200);
        assertThat(m(rec.getBody().get("openRequest")).get("kind")).isEqualTo("CORRECTION");

        // on the queue, the recommender's own; the Academic Office does not decide a correction, here or on the eligibility desk
        Map<String, Object> reg = it.get(academic, PATH + "/programme-changes").getBody();
        Map<String, Object> pending = l(reg.get("pending")).stream().filter(x -> a.app().toString().equals(String.valueOf(x.get("application_id")))).findFirst().orElseThrow();
        assertThat(pending.get("kind")).isEqualTo("CORRECTION");
        assertThat(pending.get("mine")).isEqualTo(true);
        assertThat(pending.get("admission_stage")).isEqualTo("SCHOOL_FEES_PAID");
        String reqId = String.valueOf(pending.get("id"));
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/programme-changes/requests/" + reqId + "/approve", Map.of()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/eligibility/changes/" + reqId + "/approve", Map.of()).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(a.token(), HttpMethod.POST, PATH + "/programme-changes/requests/" + reqId + "/approve", Map.of()).getStatusCode().value()).isEqualTo(403);

        // approved by the Registrar: the programme follows on the candidate and the student, the fees are kept against the new, the letter reissued
        ResponseEntity<Map> ok = it.call(registrar, HttpMethod.POST, PATH + "/programme-changes/requests/" + reqId + "/approve", Map.of("note", "Corrected to the Board's list"));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(ok.getBody().get("state")).isEqualTo("APPROVED");
        Map<String, Object> done = m(ok.getBody().get("request"));
        assertThat(((Number) done.get("fees_paid")).intValue()).isEqualTo(150000);
        assertThat(((Number) done.get("fees_due_before")).intValue()).isEqualTo(150000);
        assertThat(((Number) done.get("fees_due_after")).intValue()).isEqualTo(120000);
        assertThat(done.get("letter_reissued")).isEqualTo(true);
        assertThat(done.get("decided_office")).isEqualTo("registrar");
        assertThat(jdbc.sql("SELECT programme FROM admissions.candidate WHERE id = :c").param("c", a.candidate()).query(String.class).single()).isEqualTo("B.Sc. ACCOUNTING");
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", student).query(String.class).single()).isEqualTo(ACC);
        Map<String, Object> position = jdbc.sql("SELECT due, paid FROM finance.position(:s, :ses)").param("s", student).param("ses", SESSION).query().singleRow();
        assertThat(((BigDecimal) position.get("due")).intValue()).isEqualTo(120000);
        assertThat(((BigDecimal) position.get("paid")).intValue()).isEqualTo(150000);
        Map<String, Object> letter2 = m(it.get(a.token(), "/api/v1/applicant/me/letter").getBody());
        assertThat(((Number) letter2.get("version")).intValue()).isEqualTo(2);
        assertThat(letter2.get("number")).isEqualTo(letter1.get("number"));
        assertThat(String.valueOf(letter2.get("statement"))).contains("ACCOUNTING");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND subject ILIKE 'Your admission has been corrected%'").param("a", a.app()).query(Long.class).single()).isGreaterThanOrEqualTo(1);
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.fee_reference WHERE application_id = :a AND kind = 'ACCEPTANCE'").param("a", a.app()).query(Long.class).single()).isEqualTo(1);   // the acceptance fee stands

        // the register lists the applicant: applied for Computer Science, now Accounting, corrected, with the reason and the fees
        ResponseEntity<Map> listed = it.get(bursar, PATH + "/programme-changes");
        assertThat(listed.getStatusCode().value()).isEqualTo(200);
        Map<String, Object> row = l(listed.getBody().get("rows")).stream().filter(x -> a.app().toString().equals(String.valueOf(x.get("application_id")))).findFirst().orElseThrow();
        assertThat(row.get("applied_code")).isEqualTo(CS);
        assertThat(row.get("current_code")).isEqualTo(ACC);
        assertThat(row.get("moved")).isEqualTo(true);
        assertThat(row.get("stage")).isEqualTo("CORRECTION");
        assertThat(row.get("reason")).isEqualTo("Error discovered in the admission");
        assertThat(row.get("stage_then")).isEqualTo("SCHOOL_FEES_PAID");
        assertThat(((Number) row.get("fees_due_after")).intValue()).isEqualTo(120000);
        assertThat(String.valueOf(row.get("history"))).contains("CORRECTION").contains("B.Sc. ACCOUNTING");
        assertThat(it.get(housing, PATH + "/programme-changes").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(a.token(), PATH + "/programme-changes").getStatusCode().value()).isEqualTo(403);

        // a correction the Registrar recommends is not decided by the same officer; the Deputy Registrar rejects it, with the reason
        // (not a science UTME combination for Computer Science: only the Registrar's offices may recommend it, by override)
        ResponseEntity<Map> notEligible = it.call(academic, HttpMethod.POST, PATH + "/programme-changes/" + a.app() + "/correct",
                Map.of("programmeCode", CS, "reasonCode", "OTHER", "note", "Reconsidered on the candidate's appeal"));
        assertThat(notEligible.getStatusCode().value()).isEqualTo(422);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/programme-changes/" + a.app() + "/correct",
                Map.of("programmeCode", CS, "reasonCode", "OTHER", "note", "Reconsidered on the candidate's appeal", "override", true, "overrideReason", "x")).getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> back = it.call(registrar, HttpMethod.POST, PATH + "/programme-changes/" + a.app() + "/correct",
                Map.of("programmeCode", CS, "reasonCode", "OTHER", "note", "Reconsidered on the candidate's appeal", "override", true, "overrideReason", "The Senate's directive on the appeal"));
        assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
        String backId = String.valueOf(m(back.getBody().get("openRequest")).get("id"));
        ResponseEntity<Map> same = it.call(registrar, HttpMethod.POST, PATH + "/programme-changes/requests/" + backId + "/approve", Map.of());
        assertThat(same.getStatusCode().value()).isEqualTo(422);
        assertThat(same.getBody().get("code")).isEqualTo("CORRECTION_SAME_OFFICER");
        assertThat(it.call(dregistrar, HttpMethod.POST, PATH + "/programme-changes/requests/" + backId + "/reject", Map.of()).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> rejected = it.call(dregistrar, HttpMethod.POST, PATH + "/programme-changes/requests/" + backId + "/reject", Map.of("note", "The Board's list stands"));
        assertThat(rejected.getStatusCode().value()).as(String.valueOf(rejected.getBody())).isEqualTo(200);
        assertThat(rejected.getBody().get("state")).isEqualTo("REJECTED");
        assertThat(jdbc.sql("SELECT programme FROM admissions.candidate WHERE id = :c").param("c", a.candidate()).query(String.class).single()).isEqualTo("B.Sc. ACCOUNTING");
    }

    @Test
    void beforeTheDecisionTheOrdinaryChangeAppliesAndAfterMatriculationATransfer() {
        // the decision not yet released: the ordinary change applies, not a correction
        Applicant u = offered(CS, 212);
        it.db(() -> jdbc.sql("UPDATE admissions.application SET decision = NULL, decided_at = NULL, decision_released_at = NULL WHERE id = :a").param("a", u.app()).update());
        assertThat(it.get(academic, PATH + "/programme-changes/" + u.app() + "/preview").getBody().get("route")).isEqualTo("CHANGE");
        ResponseEntity<Map> early = it.call(academic, HttpMethod.POST, PATH + "/programme-changes/" + u.app() + "/correct", Map.of("programmeCode", ACC, "reasonCode", "ADMISSION_ERROR", "note", "x"));
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        assertThat(early.getBody().get("code")).isEqualTo("CORRECTION_NOT_NEEDED");

        // matriculated: an inter-departmental transfer, not an admission correction
        Applicant mt = offered(CS, 214);
        int n = new Random().nextInt(9000) + 1000;
        UUID st = it.db(() -> {
            UUID id = jdbc.sql("SELECT people.intake_one(:c)").param("c", mt.candidate()).query(UUID.class).single();
            jdbc.sql("UPDATE people.student SET matric_no = :m, matriculated_at = now() WHERE id = :id").param("m", "MOAUM/MTC/15/" + n + "7").param("id", id).update();
            return id;
        });
        assertThat(st).isNotNull();
        Map<String, Object> pv = it.get(academic, PATH + "/programme-changes/" + mt.app() + "/preview?to=" + ACC).getBody();
        assertThat(pv.get("route")).isEqualTo("TRANSFER");
        assertThat(pv.get("stage")).isEqualTo("MATRICULATED");
        ResponseEntity<Map> late = it.call(academic, HttpMethod.POST, PATH + "/programme-changes/" + mt.app() + "/correct", Map.of("programmeCode", ACC, "reasonCode", "ADMISSION_ERROR", "note", "x"));
        assertThat(late.getStatusCode().value()).isEqualTo(422);
        assertThat(late.getBody().get("code")).isEqualTo("CORRECTION_TRANSFER");

        // the finder names the road for each
        List<Map<String, Object>> found = l(it.getList(academic, PATH + "/programme-changes/find?q=" + mt.jamb()).getBody());
        assertThat(found).hasSize(1);
        assertThat(found.get(0).get("route")).isEqualTo("TRANSFER");
        assertThat(l(it.getList(academic, PATH + "/programme-changes/find?q=zz").getBody())).isEmpty();   // too short to search
    }
}
