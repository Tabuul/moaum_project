package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

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
 * The admission lifecycle after the offer (V269), end to end, on the existing journey: the offer and the congratulations;
 * the acceptance fee paid once and the undertaking; the online screening — opened only on acceptance, drafted on the
 * biodata catalogue with the institutions, the O'Level results as JAMB sent them, the documents, the declaration —
 * submitted only when complete and read-only after; the officer's review, the return for correction and the resubmission;
 * PATH A: successful → the application cleared, school fees and course registration open, the answers on the student
 * record; PATH B: unsuccessful with the reason → the engine's alternatives → the change of programme requested after the
 * Board's decision and approved by the Office → the acceptance fee NOT charged again → the student on the register moved to
 * the new programme → school fees open; the gates shut while the screening stands in the way; the matriculation readiness
 * naming the screening; the pipeline; the doors.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class AdmissionLifecycleIT {

    static final String SESSION = "2084/2085";
    static final String PATH = "/api/v1/admissions/sessions/2084/2085";
    static final String CS = "C00023", ACC = "C00019";
    static final UUID POLICY = UUID.fromString("e1191b1e-0000-4000-8000-000000002084");
    static final String PDF = Base64.getEncoder().encodeToString("%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%EOF".getBytes());

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String bursar = ItSupport.token("bursar");
    final String housing = ItSupport.token("housing");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2084);
        it.db(() -> {
            jdbc.sql("INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, state, instrument, in_force) VALUES (:id, :s, 1200, 70, 30, 'IN_FORCE', 'Senate minute LifecycleIT/1', tstzrange(now(), NULL)) ON CONFLICT DO NOTHING")
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

    /** an applicant offered a place and the offer released: the candidate on the CAPS list, an account, the application at stage 5, O'Level as JAMB sent it */
    Applicant offered(String programme, int score, List<String> utme, List<Map<String, String>> sitting) {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = "2084" + n + "LC";
        String surname = "ZZLIFE-" + n;
        return it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), appId = UUID.randomUUID(), batch = UUID.randomUUID(), att = UUID.randomUUID(), sit = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) VALUES (:id, :s, :j, :sn, 'Test Person', (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, 'PROPOSED')")
                    .param("id", cand).param("s", SESSION).param("j", jamb).param("sn", surname).param("p", programme).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at, score_released_at, decision, decision_basis, decided_at, decision_released_at) VALUES (:id, :a, :c, :s, :no, now(), now(), now(), 'OFFERED', 'NM', now(), now())")
                    .param("id", appId).param("a", acct).param("c", cand).param("s", SESSION).param("no", "APP/84/" + String.format("%06d", n % 1_000_000)).update();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) VALUES (:id, :s, 'CAPS_DOWNLOAD', 'life.xlsx', decode(md5(:id::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga) VALUES (gen_random_uuid(), :b, :s, :j, jsonb_build_object('Subject1', :s1, 'Subject2', :s2, 'Subject3', :s3, 'Subject4', :s4), :sn, 'Test Person', :p, :agg, 'UTME', 'F', 'Benue', 'Gboko')")
                    .param("b", batch).param("s", SESSION).param("j", jamb).param("s1", utme.get(0)).param("s2", utme.get(1)).param("s3", utme.get(2)).param("s4", utme.get(3)).param("sn", surname).param("p", programme).param("agg", score).update();
            jdbc.sql("UPDATE admissions.candidate SET offer_state = 'ADMITTED', admitted_from = (SELECT id FROM admissions.caps_row WHERE session = :s AND jamb_reg_no = :j) WHERE id = :c").param("s", SESSION).param("j", jamb).param("c", cand).update();
            jdbc.sql("INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at) VALUES (:id, :s, 'OLEVEL', :n, :k, 'EXACT', :c, now())")
                    .param("id", att).param("s", SESSION).param("n", jamb + "-olevel.json").param("k", jamb).param("c", cand).update();
            jdbc.sql("INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_year, exam_number, ord) VALUES (:id, :a, :s, :k, 'WAEC', '2083', :no, 1)")
                    .param("id", sit).param("a", att).param("s", SESSION).param("k", jamb).param("no", "WAEC/" + n).update();
            for (Map<String, String> g : sitting) jdbc.sql("INSERT INTO admissions.olevel_grade (sitting_id, subject, grade) VALUES (:s, :j, :g)").param("s", sit).param("j", g.get("s")).param("g", g.get("g")).update();
            return new Applicant(appId, acct, cand, jamb, surname, TestTokens.token(acct, List.of("applicant")));
        });
    }

    static Map<String, String> g(String s, String gr) { return Map.of("s", s, "g", gr); }
    static final List<Map<String, String>> SCIENCE = List.of(g("English Language", "C6"), g("Mathematics", "B3"), g("Physics", "C5"), g("Chemistry", "C6"), g("Biology", "C4"), g("Economics", "B3"));
    static final List<Map<String, String>> COMMERCIAL = List.of(g("English Language", "B3"), g("Mathematics", "C6"), g("Economics", "B2"), g("Accounting", "C5"), g("Commerce", "C6"), g("Government", "B3"));

    @SuppressWarnings("unchecked")
    static Map<String, Object> m(Object o) { return (Map<String, Object>) o; }
    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> l(Object o) { return (List<Map<String, Object>>) o; }

    Map<String, Object> admission(Applicant a) { return m(it.get(a.token(), "/api/v1/applicant/me/admission").getBody()); }

    /** the acceptance as the journey already does it: the undertaking, the fee reference, the Bursary's confirmation */
    /** the admission checking fee, on its own, opens the decision (V271) */
    void check(Applicant a) {
        ResponseEntity<Map> ref = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "CHECKING"));
        assertThat(ref.getStatusCode().value()).as(String.valueOf(ref.getBody())).isEqualTo(200);
        String r = String.valueOf(ref.getBody().get("reference"));
        assertThat(r).startsWith("MOAUM-CHK-");
        assertThat(jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", r).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("3000");
        assertThat(it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + r + "/confirm", Map.of("channel", "Card")).getStatusCode().value()).isEqualTo(200);
    }

    void accept(Applicant a) {
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/accept", Map.of("undertaking", true)).getStatusCode().value()).isEqualTo(200);
        String ref = String.valueOf(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getBody().get("reference"));
        assertThat(ref).startsWith("MOAUM-ACC-");
        assertThat(jdbc.sql("SELECT amount FROM admissions.fee_reference WHERE reference = :r").param("r", ref).query(java.math.BigDecimal.class).single()).isEqualByComparingTo("25000");   // the acceptance fee alone
        ResponseEntity<Map> c = it.call(bursar, HttpMethod.POST, PATH + "/fee-references/" + ref + "/confirm", Map.of("channel", "Card"));
        assertThat(c.getStatusCode().value()).as(String.valueOf(c.getBody())).isEqualTo(200);
    }

    Map<String, Object> answers() {
        return Map.ofEntries(Map.entry("nationality", "Nigeria"), Map.entry("state_of_origin", "Benue"), Map.entry("lga", "Gboko"), Map.entry("religion", "Christianity"), Map.entry("marital_status", "Single"),
                Map.entry("home_address", "No. 26 Dagye Street, Kaduna"), Map.entry("mobile", "08031234567"), Map.entry("sponsor_name", "Mrs Rebecca Test"), Map.entry("sponsor_address", "No. 26 Dagye Street, Kaduna"),
                Map.entry("kin_name", "Wilfred Test"), Map.entry("kin_mobile", "09040519378"), Map.entry("kin_relationship", "Father"), Map.entry("secondary_school", "Gwazachat Academy, Sabo Tasha"), Map.entry("secondary_graduation_year", "2020"),
                Map.entry("parent_profession", "Businessman"), Map.entry("primary_school", "Righton International School"));
    }

    void upload(Applicant a, String kind) {
        ResponseEntity<Map> r = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/documents", Map.of("kind", kind, "filename", kind.toLowerCase() + ".pdf", "contentType", "application/pdf", "contentBase64", PDF));
        assertThat(r.getStatusCode().value()).as(kind + ": " + r.getBody()).isEqualTo(200);
    }

    UUID intake(Applicant a) {
        return it.db(() -> {
            jdbc.sql("SELECT people.intake(:s)").param("s", SESSION).query().listOfRows();
            return jdbc.sql("SELECT id FROM people.student WHERE candidate_id = :c").param("c", a.candidate()).query(UUID.class).single();
        });
    }

    @Test
    void theLifecycleFromTheOfferToMatriculationReadinessOnBothPaths() {
        Applicant a = offered(CS, 210, List.of("English Language", "Mathematics", "Physics", "Chemistry"), SCIENCE);                 // PATH A
        Applicant b = offered(CS, 210, List.of("English Language", "Mathematics", "Economics", "Government"), COMMERCIAL);           // PATH B: not a science candidate

        // V272: a session with no fees of its own carries the last stated session's forward — the checking fee is never silently nought
        Map<String, Object> carried = jdbc.sql("SELECT * FROM admissions.applicant_fee_rule('1999/2000')").query().singleRow();
        assertThat(carried.get("stated")).isEqualTo(false);
        assertThat(carried.get("carried_from")).isNotNull();
        assertThat(((java.math.BigDecimal) carried.get("checking_fee")).signum()).isPositive();
        // 3–6 · the decision is released; the admission checking fee, on its own, opens it (V271) — nothing of the decision shows before
        Map<String, Object> st = admission(a);
        assertThat(st.get("status")).isEqualTo("CHECKING_FEE_PENDING");
        assertThat(m(st.get("offer")).get("decision")).isNull();
        assertThat(m(st.get("offer")).get("programme")).isNull();
        assertThat(it.get(a.token(), "/api/v1/applicant/me").getBody().get("decision")).isNull();
        assertThat(it.get(a.token(), "/api/v1/applicant/me").getBody().get("checkingDue")).isEqualTo(true);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getStatusCode().value()).isEqualTo(422);   // the checking fee comes first
        check(a);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "CHECKING")).getStatusCode().value()).isEqualTo(422);      // paid once
        st = admission(a);
        assertThat(st.get("status")).isEqualTo("ADMITTED");
        assertThat(it.get(a.token(), "/api/v1/applicant/me").getBody().get("decision")).isEqualTo("OFFERED");
        // the status is read on the confirmation of the checking fee; the acceptance fee is the next step
        assertThat(String.valueOf(st.get("next_action"))).contains("acceptance fee");
        assertThat(m(st.get("entitlement")).get("checking_paid")).isEqualTo(true);
        assertThat(String.valueOf(st.get("tracker"))).contains("\"key\": \"ADMISSION_STATUS\", \"label\": \"Admission status checked\", \"state\": \"done\"").contains("\"key\": \"SCHOOL_FEES\", \"label\": \"School fees\", \"state\": \"todo\"");
        assertThat(jdbc.sql("SELECT status_checked_at FROM admissions.application WHERE id = :a").param("a", a.app()).query().singleRow().get("status_checked_at")).isNotNull();
        check(b);
        assertThat(m(st.get("offer")).get("decision")).isEqualTo("OFFERED");
        assertThat(m(st.get("offer")).get("faculty")).isNotNull();
        assertThat(m(st.get("entitlement")).get("paid")).isEqualTo(false);
        assertThat(String.valueOf(st.get("tracker"))).contains("\"ADMISSION\"").contains("\"ADMISSION_STATUS\"").contains("\"ACCEPTANCE_PAYMENT\"").contains("\"SCREENING\"");
        // V270: admitted from the list without a CBT slip or score, the journey stands at the decision (stage 5), not behind the screening slip
        assertThat(it.get(a.token(), "/api/v1/applicant/me").getBody().get("stage")).isEqualTo(5);
        // 8 / 28 · the screening does not open before acceptance; nothing is saved
        assertThat(m(it.get(a.token(), "/api/v1/applicant/me/screening").getBody()).get("form")).isNull();
        assertThat(it.call(a.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", answers())).getStatusCode().value()).isEqualTo(422);

        // 5–7 · acceptance: the fee once, the undertaking; the letter door opens; a second acceptance reference is refused
        accept(a);
        accept(b);
        st = admission(a);
        assertThat(st.get("status")).isEqualTo("SCREENING_PENDING");
        assertThat(m(st.get("entitlement")).get("paid")).isEqualTo(true);
        assertThat(m(st.get("offer")).get("accepted_at")).isNotNull();
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getStatusCode().value()).isEqualTo(422);   // 33

        // 8–9 · the screening form: opened on acceptance, prefilled with JAMB's O'Level, drafted, incomplete refused, documents, declaration, submitted
        Map<String, Object> sv = m(it.get(a.token(), "/api/v1/applicant/me/screening").getBody());
        Map<String, Object> form = m(sv.get("form"));
        assertThat(form.get("state")).isEqualTo("DRAFT");
        assertThat(String.valueOf(form.get("screening_no"))).matches("SCR/2084/\\d{6}");
        assertThat(l(sv.get("olevel"))).hasSize(SCIENCE.size());
        assertThat(l(sv.get("fields")).stream().map(f -> f.get("field"))).contains("secondary_school", "parent_profession", "sponsor_name", "kin_name");
        ResponseEntity<Map> saved = it.call(a.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", answers(),
                "institutions", List.of(Map.of("name", "Righton International School", "from_year", 2070, "to_year", 2076, "certificate", "FSLC", "award_year", 2076), Map.of("name", "Gwazachat Academy", "from_year", 2077, "to_year", 2083, "certificate", "SSCE", "award_year", 2083)),
                "membership", "Debating society"));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(l(saved.getBody().get("institutions"))).hasSize(2);
        assertThat(l(saved.getBody().get("answers"))).anyMatch(x -> "secondary_school".equals(x.get("field")));
        assertThat(l(saved.getBody().get("missing")).stream().map(x -> x.get("kind"))).contains("DOCUMENT").doesNotContain("FIELD", "OLEVEL");
        // V273: the lists the form chooses from, and the shape of what was given checked before submission
        List<Map<String, Object>> states = it.getList(a.token(), "/api/v1/ref/states").getBody();
        assertThat(states).hasSize(37);
        assertThat(String.valueOf(states.stream().filter(x -> "Benue".equals(x.get("name"))).findFirst().orElseThrow().get("lgas"))).contains("Gboko").contains("Gwer East");
        assertThat(l(it.getList(a.token(), "/api/v1/ref/countries").getBody()).size() > 0 || it.getList(a.token(), "/api/v1/ref/countries").getBody().get(0).equals("Nigeria")).isTrue();
        Map<String, Object> badSaved = m(it.call(a.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", Map.of("mobile", "0803", "lga", "Awka", "personal_email", "not-an-email"))).getBody());
        assertThat(l(badSaved.get("missing")).stream().filter(x -> "INVALID".equals(x.get("kind"))).map(x -> x.get("item"))).contains("mobile", "lga", "personal_email");
        assertThat(it.call(a.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", Map.of("mobile", "08031234567", "lga", "Gboko", "personal_email", ""))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> early = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/screening/submit", Map.of("declaration", true));
        assertThat(early.getStatusCode().value()).isEqualTo(422);
        for (String k : List.of("OLEVEL_STATEMENT", "JAMB_SLIP", "BIRTH_CERT", "LGA_ID", "PASSPORT")) upload(a, k);
        assertThat(it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/screening/submit", Map.of("declaration", false)).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> submitted = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/screening/submit", Map.of("declaration", true));
        assertThat(submitted.getStatusCode().value()).as(String.valueOf(submitted.getBody())).isEqualTo(200);
        assertThat(m(submitted.getBody().get("form")).get("state")).isEqualTo("SUBMITTED");
        assertThat(m(submitted.getBody().get("status")).get("status")).isEqualTo("SCREENING_SUBMITTED");
        // 11 · read-only once submitted
        assertThat(it.call(a.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", Map.of("religion", "Other"))).getStatusCode().value()).isEqualTo(422);
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND subject ILIKE '%screening form has been received%'").param("a", a.app()).query(Long.class).single()).isGreaterThanOrEqualTo(1);
        // 29 / 27 · the gates are shut while the screening stands: no school-fee reference, no registration (the student not yet on the register, so through the function)
        UUID sa = intake(a);
        assertThat(jdbc.sql("SELECT admissions.screening_ok_student(:s)").param("s", sa).query(Boolean.class).single()).isFalse();
        assertThat(it.db(() -> { try { jdbc.sql("SELECT finance.new_reference(:s, :ses, 1000, 'test')").param("s", sa).param("ses", SESSION).query(String.class).single(); return "opened"; } catch (org.springframework.dao.DataAccessException e) { return e.getMostSpecificCause().getMessage(); } })).contains("SCHOOL FEES UNAVAILABLE");
        assertThat(it.db(() -> { try { jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status) VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'DRAFT')").param("s", sa).param("ses", SESSION).update(); return "opened"; } catch (org.springframework.dao.DataAccessException e) { return e.getMostSpecificCause().getMessage(); } })).contains("COURSE REGISTRATION UNAVAILABLE");

        // 12 · the officers' queue and the review
        Map<String, Object> queue = m(it.get(academic, PATH + "/screening-review?state=SUBMITTED&q=" + a.surname()).getBody());
        assertThat(l(queue.get("rows"))).hasSize(1);
        assertThat(((Number) m(queue.get("stats")).get("submitted")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(it.get(housing, PATH + "/screening-review").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(a.token(), PATH + "/screening-review").getStatusCode().value()).isEqualTo(403);
        ResponseEntity<Map> det = it.get(academic, PATH + "/screening-review/" + a.app());
        assertThat(det.getStatusCode().value()).isEqualTo(200);
        assertThat(l(det.getBody().get("answers"))).isNotEmpty();
        assertThat(l(det.getBody().get("documents"))).hasSize(5);
        assertThat(l(det.getBody().get("jambOlevel"))).hasSize(SCIENCE.size());
        String docId = String.valueOf(l(det.getBody().get("documents")).get(0).get("id"));
        assertThat(it.getBytes(academic, PATH + "/applications/" + a.app() + "/documents/" + docId + "/content").getStatusCode().value()).isEqualTo(200);      // 31: the office's door
        assertThat(it.getBytes(b.token(), "/api/v1/applicant/me/documents/" + docId + "/content").getStatusCode().value()).isIn(403, 404);            // 31: another applicant's door
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/start", Map.of()).getStatusCode().value()).isEqualTo(200);
        // returned for correction, corrected, resubmitted as version 2
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/decide", Map.of("decision", "RETURNED", "reason", "")).getStatusCode().value()).isIn(400, 422);
        ResponseEntity<Map> ret = it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/decide", Map.of("decision", "RETURNED", "reason", "The sponsor's address is incomplete"));
        assertThat(ret.getStatusCode().value()).as(String.valueOf(ret.getBody())).isEqualTo(200);
        assertThat(admission(a).get("status")).isEqualTo("SCREENING_RETURNED");
        assertThat(it.call(a.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", Map.of("sponsor_address", "No. 26 Dagye Street, Kaduna, Kaduna State"))).getStatusCode().value()).isEqualTo(200);
        ResponseEntity<Map> again = it.call(a.token(), HttpMethod.POST, "/api/v1/applicant/me/screening/submit", Map.of("declaration", true));
        assertThat(((Number) m(again.getBody().get("form")).get("version")).intValue()).isEqualTo(2);

        // 13 · PATH A: successful → cleared, school fees open, the answers on the student record
        ResponseEntity<Map> ok = it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/decide", Map.of("decision", "SUCCESSFUL", "remarks", "All originals sighted"));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(m(ok.getBody().get("form")).get("state")).isEqualTo("SUCCESSFUL");
        assertThat(jdbc.sql("SELECT cleared_at FROM admissions.application WHERE id = :a").param("a", a.app()).query().singleRow().get("cleared_at")).isNotNull();
        assertThat(jdbc.sql("SELECT admissions.screening_ok_student(:s)").param("s", sa).query(Boolean.class).single()).isTrue();
        assertThat(jdbc.sql("SELECT value FROM people.biodata WHERE student_id = :s AND field = 'secondary_school'").param("s", sa).query(String.class).single()).contains("Gwazachat");
        // no fee schedule is stated for the test session, so the fees read as settled and the status moves straight on
        assertThat(admission(a).get("status")).isIn("SCHOOL_FEES_PENDING", "COURSE_REGISTRATION_PENDING");
        assertThat(it.db(() -> { try { jdbc.sql("SELECT finance.new_reference(:s, :ses, 1000, 'test')").param("s", sa).param("ses", SESSION).query(String.class).single(); return "opened"; } catch (org.springframework.dao.DataAccessException e) { return e.getMostSpecificCause().getMessage(); } })).doesNotContain("SCHOOL FEES UNAVAILABLE");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND subject ILIKE '%successfully screened%'").param("a", a.app()).query(Long.class).single()).isGreaterThanOrEqualTo(1);
        // 16–18 · registration opens (the gate lets the insert through), the readiness reads it, the matriculation candidates no longer name the screening
        it.db(() -> jdbc.sql("INSERT INTO registration.course_registration (id, student_id, session, semester, level, status, approved_at) VALUES (gen_random_uuid(), :s, :ses, 1, 100, 'APPROVED', now()) ON CONFLICT (student_id, session, semester) DO UPDATE SET status = 'APPROVED'").param("s", sa).param("ses", SESSION).update());
        // registered; the fees stay pending until the Bursary states the session's schedule (V271: nothing due is not "paid")
        assertThat(admission(a).get("status")).isIn("MATRICULATION_PENDING", "SCHOOL_FEES_PENDING");
        assertThat(jdbc.sql("SELECT reason FROM people.matric_candidates(:s, 'SC') x WHERE x.student_id = :id").param("s", SESSION).param("id", sa).query().singleRow().get("reason")).isNull();

        // 13–17 · PATH B: unsuccessful with the reason → alternatives → change requested after the Board's decision → approved → no second acceptance fee
        Map<String, Object> bv = m(it.get(b.token(), "/api/v1/applicant/me/screening").getBody());
        assertThat(m(bv.get("form")).get("state")).isEqualTo("DRAFT");
        it.call(b.token(), HttpMethod.PUT, "/api/v1/applicant/me/screening", Map.of("answers", answers()));
        for (String k : List.of("OLEVEL_STATEMENT", "JAMB_SLIP", "BIRTH_CERT", "LGA_ID", "PASSPORT")) upload(b, k);
        assertThat(it.call(b.token(), HttpMethod.POST, "/api/v1/applicant/me/screening/submit", Map.of("declaration", true)).getStatusCode().value()).isEqualTo(200);
        UUID sb = intake(b);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + b.app() + "/decide", Map.of("decision", "UNSUCCESSFUL")).getStatusCode().value()).isEqualTo(422);
        ResponseEntity<Map> bad = it.call(academic, HttpMethod.POST, PATH + "/screening-review/" + b.app() + "/decide", Map.of("decision", "UNSUCCESSFUL", "reason", "No credit in Physics; the science combination is not met", "remarks", "Eligible for Accounting"));
        assertThat(bad.getStatusCode().value()).as(String.valueOf(bad.getBody())).isEqualTo(200);
        assertThat(m(bad.getBody().get("eligibility")).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        assertThat(String.valueOf(m(bad.getBody().get("eligibility")).get("eligible_alternatives"))).contains("ACCOUNTING");
        Map<String, Object> bst = admission(b);
        assertThat(bst.get("status")).isEqualTo("CHANGE_OF_PROGRAMME_REQUIRED");
        assertThat(String.valueOf(bst.get("tracker"))).contains("\"CHANGE_OF_PROGRAMME\"").contains("\"failed\"");
        assertThat(jdbc.sql("SELECT reason FROM people.matric_candidates(:s, 'SC') x WHERE x.student_id = :id").param("s", SESSION).param("id", sb).query(String.class).single()).contains("screening");
        // the applicant asks for a listed programme; a second acceptance fee is refused; the Office approves
        Map<String, Object> el = m(it.get(b.token(), "/api/v1/applicant/me/eligibility").getBody());
        assertThat(l(el.get("alternatives")).stream().map(x -> x.get("programme_code"))).contains(ACC);
        ResponseEntity<Map> asked = it.call(b.token(), HttpMethod.POST, "/api/v1/applicant/me/eligibility/change", Map.of("programmeCode", ACC, "note", "Accounting after the screening"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        assertThat(admission(b).get("status")).isEqualTo("CHANGE_OF_PROGRAMME_PENDING");
        assertThat(it.call(b.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "ACCEPTANCE")).getStatusCode().value()).isEqualTo(422);
        String reqId = String.valueOf(l(asked.getBody().get("changes")).get(0).get("id"));
        ResponseEntity<Map> approved = it.call(academic, HttpMethod.POST, PATH + "/eligibility/changes/" + reqId + "/approve", Map.of("note", "Within quota"));
        assertThat(approved.getStatusCode().value()).as(String.valueOf(approved.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT programme FROM admissions.candidate WHERE id = :c").param("c", b.candidate()).query(String.class).single()).isEqualTo("B.Sc. ACCOUNTING");
        assertThat(jdbc.sql("SELECT programme_code FROM people.student WHERE id = :s").param("s", sb).query(String.class).single()).isEqualTo(ACC);
        assertThat(jdbc.sql("SELECT id FROM people.student WHERE candidate_id = :c").param("c", b.candidate()).query(UUID.class).single()).isEqualTo(sb);   // 12/23: the same student
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.fee_reference WHERE application_id = :a AND kind = 'ACCEPTANCE'").param("a", b.app()).query(Long.class).single()).isEqualTo(1);   // 13/33
        assertThat(jdbc.sql("SELECT admissions.screening_ok_student(:s)").param("s", sb).query(Boolean.class).single()).isTrue();
        bst = admission(b);
        assertThat(bst.get("status")).isIn("SCHOOL_FEES_PENDING", "COURSE_REGISTRATION_PENDING");
        assertThat(m(bst.get("offer")).get("changed_to")).isEqualTo("B.Sc. ACCOUNTING");
        assertThat(m(bst.get("entitlement")).get("paid")).isEqualTo(true);
        assertThat(m(bst.get("entitlement")).get("checking_paid")).isEqualTo(true);
        assertThat(it.call(b.token(), HttpMethod.POST, "/api/v1/applicant/me/fee-references", Map.of("kind", "CHECKING")).getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(bst.get("tracker"))).contains("\"key\": \"CHANGE_APPROVAL\", \"label\": \"Approval\", \"state\": \"done\"").contains("\"key\": \"SCREENING_DECISION\", \"label\": \"Screening unsuccessful\", \"state\": \"failed\"");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND subject ILIKE '%next step: school fees%'").param("a", b.app()).query(Long.class).single()).isGreaterThanOrEqualTo(1);
        assertThat(String.valueOf(jdbc.sql("SELECT reason FROM people.matric_candidates(:s, 'MS') x WHERE x.student_id = :id").param("s", SESSION).param("id", sb).query().singleRow().get("reason"))).doesNotContain("screening").contains("course registration");

        // 27 · the pipeline counts both paths
        Map<String, Object> pipe = m(it.get(academic, PATH + "/pipeline").getBody());
        assertThat(((Number) pipe.get("admitted")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) pipe.get("screening_successful")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) pipe.get("screening_unsuccessful")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) pipe.get("change_approved")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) pipe.get("ready_for_matric")).intValue()).isGreaterThanOrEqualTo(1);
        // the desk's completed filter carries both
        Map<String, Object> done = m(it.get(academic, PATH + "/screening-review?state=COMPLETED&q=ZZLIFE-").getBody());
        assertThat(l(done.get("rows")).stream().map(r -> r.get("id"))).contains(a.app().toString(), b.app().toString());
        // 32 · the applicant cannot decide their own screening or approve their own change
        assertThat(it.call(a.token(), HttpMethod.POST, PATH + "/screening-review/" + a.app() + "/decide", Map.of("decision", "SUCCESSFUL")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(b.token(), HttpMethod.POST, PATH + "/eligibility/changes/" + reqId + "/approve", Map.of()).getStatusCode().value()).isEqualTo(403);
    }
}
