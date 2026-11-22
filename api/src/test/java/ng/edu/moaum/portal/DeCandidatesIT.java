package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.time.LocalDate;
import java.time.Period;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.LinkedHashMap;
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
 * V773: the Direct Entry candidates with their qualifications through the API, in a session of its own with its own admission
 * settings in force: DOCTOR OF PHARMACY (C73770; five O'Level credits in two sittings, its O'Level subjects English Language,
 * Mathematics, Physics, Chemistry and Biology) and LL.B (LAW) (C00033). Made-up candidates on JAMB's lists — P1 to P4 and P6 on
 * Pharmacy's Direct Entry list, P5 on Law's, U1 on Pharmacy's UTME list — of whom P1, P3 and P5 have registered; P2, not cleared on
 * JAMB's list, holds an A-Level typed by hand (A B C); P1 and P3 hold O'Level, P3 without a credit in Mathematics and with a date
 * of birth. Pharmacy is given its own Preliminary Fit rule (and every refusal of a rule is met); a workbook of nine rows is
 * previewed (nothing kept), recorded, and recorded again (nothing changes); the download ranks everyone on the list by score —
 * registered or not — with the fit, the reason and the O'Level check; the settings begin the next session with the rule; a degree
 * and an NCE's double major are typed by hand; a candidate who has not registered is found by REG NO.; and the offices that do not
 * upload or read are refused.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class DeCandidatesIT {

    static final String PHARM = "C73770";
    static final String LAW = "C00033";
    /** every key a fully populated row carries, less otherNotes (GET …/de-candidates) */
    static final String[] ROW_KEYS = {"rank", "listNo", "regNo", "name", "state", "lga", "sex", "capsQualification", "capsGrade",
        "hasFiveCredits", "isCleared", "status", "age", "ageQualified", "admissionCategory", "registered", "qualificationType", "basis",
        "discipline", "grades", "points", "maxPoints", "score", "classPoints", "institution", "year", "examNo", "fit", "reason",
        "olevelResults", "olevelSittings", "sittings", "olevelGrades", "keyCredits", "keyOf", "totalCredits", "olevelCheck", "olevelCheckKind"};

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

    /** one row of the workbook as the screen sends it: every key, the blank ones null */
    private static Map<String, Object> row(int line, String regNo, String typeText, String basis) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("line", line);
        r.put("regNo", regNo);
        for (String k : List.of("capsQualification", "capsGrade", "hasFiveCredits", "isCleared", "status", "age", "ageQualified", "admissionCategory")) {
            r.put(k, null);
        }
        r.put("typeText", typeText);
        r.put("basis", basis);
        r.put("discipline", null);
        r.put("awardClass", null);
        r.put("subjects", new ArrayList<Map<String, Object>>());
        r.put("institution", null);
        r.put("year", null);
        r.put("examNo", null);
        r.put("notes", List.of());
        return r;
    }

    private static List<Map<String, Object>> subjects(String... subjectThenGrade) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (int i = 0; i < subjectThenGrade.length; i += 2) {
            Map<String, Object> s = new HashMap<>();
            s.put("subject", subjectThenGrade[i]);
            s.put("grade", subjectThenGrade[i + 1]);
            out.add(s);
        }
        return out;
    }

    /** one kind's Preliminary Fit rule as the editor sends it */
    private static Map<String, Object> rule(String kind, List<String> core, Integer relevantMin, Integer partlyMin, List<String> related,
                                            Integer relatedRelevantMin, Integer relatedPartlyMin, String otherFit, Integer relevantPasses, Integer partlyPasses) {
        Map<String, Object> r = new LinkedHashMap<>();
        r.put("kind", kind);
        r.put("coreDisciplines", core);
        r.put("relevantMin", relevantMin);
        r.put("partlyMin", partlyMin);
        r.put("relatedDisciplines", related);
        r.put("relatedRelevantMin", relatedRelevantMin);
        r.put("relatedPartlyMin", relatedPartlyMin);
        r.put("otherFit", otherFit);
        r.put("relevantPasses", relevantPasses);
        r.put("partlyPasses", partlyPasses);
        return r;
    }

    /** DOCTOR OF PHARMACY's own rule, as its Fit Criteria sheet states it (the 2026/2027 seed) */
    private static List<Map<String, Object>> pharmacyRule() {
        List<Map<String, Object>> rows = new ArrayList<>();
        rows.add(rule("DEGREE", List.of("Chemistry", "Biochemistry", "Pharmacology", "Microbiology", "Physiology", "Anatomy",
                "Medical Laboratory Science", "Nursing", "Biology", "Zoology"), 4, 3,
                List.of("Physics", "Forestry", "Botany/Plant Science", "Agriculture/Agricultural Science", "Food Science", "Biomedical Technology",
                        "Laboratory Technology"), null, 3, "NOT_RELEVANT", null, null));
        rows.add(rule("UNIVERSITY_DIPLOMA", List.of(), null, null, List.of(), null, null, "CHECK_MANUALLY", null, null));
        rows.add(rule("HND", List.of("Pharmaceutical Technology/Pharmacy Technician"), null, 2, List.of(), null, null, "NOT_RELEVANT", null, null));
        rows.add(rule("ND", List.of("Pharmaceutical Technology/Pharmacy Technician"), null, 1, List.of(), null, null, "NOT_RELEVANT", null, null));
        rows.add(rule("NCE", List.of(), null, null, List.of(), null, null, "CHECK_MANUALLY", null, null));
        rows.add(rule("A_LEVEL", List.of("Biology/Zoology/Botany", "Chemistry", "Physics"), 3, 1, List.of(), null, null, "NOT_RELEVANT", 3, 3));
        return rows;
    }

    /** the rule with one kind's row changed */
    private static List<Map<String, Object>> pharmacyRuleWith(String kind, String key, Object value) {
        List<Map<String, Object>> rows = pharmacyRule();
        rows.stream().filter(r -> kind.equals(r.get("kind"))).forEach(r -> r.put(key, value));
        return rows;
    }

    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> rowsOf(Map<?, ?> body) {
        return (List<Map<String, Object>>) body.get("rows");
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> ownRule(Map<?, ?> fit, String code) {
        return ((List<Map<String, Object>>) fit.get("programmes")).stream().filter(p -> code.equals(p.get("code"))).findFirst().orElse(null);
    }

    @Test
    @SuppressWarnings({"unchecked", "rawtypes"})
    void aWorkbookOfQualificationsIsRecordedOnceAndTheSheetRanksEveryoneOnJambsDirectEntryList() {
        int y = it.freeYear(7800, 7900, 0, 1);
        String ses = y + "/" + (y + 1);
        String yy = String.format("%02d", (y + 1) % 100);
        String base = "/api/v1/admissions/sessions/" + y + "/" + (y + 1);
        String pharmacy = it.db(() -> jdbc.sql("SELECT name FROM ref.programme WHERE code = :c").param("c", PHARM).query(String.class).single());
        String law = it.db(() -> jdbc.sql("SELECT name FROM ref.programme WHERE code = :c").param("c", LAW).query(String.class).single());
        UUID pol = UUID.randomUUID(), grp = UUID.randomUUID(), batch = UUID.randomUUID(), ubatch = UUID.randomUUID(), who = UUID.randomUUID();
        // the uploader is a person: a recorded qualification names who recorded it
        String academic = TestTokens.token(who, List.of("academic"));
        it.db(() -> {
            jdbc.sql("INSERT INTO iam.person (id, surname, given_names) VALUES (:w, 'ZZDECIT', 'Recorder')").param("w", who).update();
            for (int x = y; x <= y + 1; x++) {
                jdbc.sql("INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), :s, make_date(:y, 10, 1), make_date(:y + 1, 8, 31)) ON CONFLICT (name) DO NOTHING")
                        .param("s", x + "/" + (x + 1)).param("y", x).update();
            }
            jdbc.sql("""
                    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, instrument, in_force, state)
                    VALUES (:p, :s, 10, 70, 30, 80, 20, 'IT CAC/DEC/1', tstzrange(now(), NULL), 'IN_FORCE')
                    """).param("p", pol).param("s", ses).update();
            jdbc.sql("""
                    INSERT INTO admissions.programme_rule (policy_id, programme_code, quota, olevel_credits, olevel_sittings, olevel_text, utme_text, de_text)
                    VALUES (:p, :c, 10, 5, 2, 'English Language, Mathematics, Physics, Chemistry and Biology', 'it', 'it'), (:p, :l, 10, 5, 2, 'it', 'it', 'it')
                    """).param("p", pol).param("c", PHARM).param("l", LAW).update();
            jdbc.sql("INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose) VALUES (:g, :p, :c, 'OLEVEL', 5)")
                    .param("g", grp).param("p", pol).param("c", PHARM).update();
            jdbc.sql("INSERT INTO admissions.rule_subject (group_id, subject) VALUES (:g, 'English Language'), (:g, 'Mathematics'), (:g, 'Physics'), (:g, 'Chemistry'), (:g, 'Biology')")
                    .param("g", grp).update();
            jdbc.sql("""
                    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
                    VALUES (:b, :s, 'CAPS_DOWNLOAD', 'DIRECT_ENTRY', decode(md5(:s || 'de'), 'hex'), 6, current_date, :w, 'academic'),
                           (:u, :s, 'CAPS_DOWNLOAD', 'UTME', decode(md5(:s || 'utme'), 'hex'), 1, current_date, :w, 'academic')
                    """).param("b", batch).param("u", ubatch).param("s", ses).param("w", who).update();
            return null;
        });
        String[][] people = {
            // tag, programme, mode, registered, IsDECleared on JAMB's list
            {"P1", PHARM, "DIRECT_ENTRY", "yes", "1"},
            {"P2", PHARM, "DIRECT_ENTRY", "no", "0"},
            {"P3", PHARM, "DIRECT_ENTRY", "yes", "1"},
            {"P4", PHARM, "DIRECT_ENTRY", "no", "1"},
            {"P5", LAW, "DIRECT_ENTRY", "yes", "1"},
            {"P6", PHARM, "DIRECT_ENTRY", "no", "1"},
            {"U1", PHARM, "UTME", "no", "1"},
        };
        Map<String, String> jamb = new HashMap<>();
        Map<String, UUID> cands = new HashMap<>();
        for (int i = 0; i < people.length; i++) {
            String[] p = people[i];
            String j = y + "78000" + (i + 1) + "ZQ";
            jamb.put(p[0], j);
            int n = i;
            UUID made = it.db(() -> {
                UUID cr = UUID.randomUUID(), cand = UUID.randomUUID(), acct = UUID.randomUUID();
                boolean utme = "UTME".equals(p[2]);
                jdbc.sql("""
                        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
                        VALUES (:id, :b, :s, :j, jsonb_build_object('IsDECleared', :cl::text), 'ZZDECIT', :t, :c, :agg, :m, 'F', 'Benue', 'Makurdi')
                        """).param("id", cr).param("b", utme ? ubatch : batch).param("s", ses).param("j", j).param("cl", p[4]).param("t", p[0]).param("c", p[1])
                        .param("agg", utme ? 250 : null, java.sql.Types.INTEGER).param("m", p[2]).update();
                if (!"yes".equals(p[3])) {
                    return null;
                }
                jdbc.sql("""
                        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
                        VALUES (:id, :s, :j, 'ZZDECIT', :t, (SELECT name FROM ref.programme WHERE code = :c), :m, :lvl, 'PROPOSED', :cr)
                        """).param("id", cand).param("s", ses).param("j", j).param("t", p[0]).param("c", p[1]).param("m", p[2])
                        .param("lvl", utme ? 100 : 200).param("cr", cr).update();
                jdbc.sql("""
                        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
                        VALUES (:id, :s, :c, :j, lower(:j) || '@example.com', '08030007730', 'SET_ON_FIRST_LOGIN')
                        """).param("id", acct).param("s", ses).param("c", cand).param("j", j).update();
                jdbc.sql("""
                        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at)
                        VALUES (gen_random_uuid(), :acct, :c, :s, :no, now(), now())
                        """).param("acct", acct).param("c", cand).param("s", ses)
                        .param("no", "APP/" + yy + "/78" + String.format("%04d", (y % 100) * 10 + n)).update();
                return cand;
            });
            if (made != null) {
                cands.put(p[0], made);
            }
        }
        // O'Level: P1 the five subjects in one sitting; P3 without a credit in Mathematics, and a date of birth
        String[][][] olevel = {
            {{"P1"}, {"English Language", "B3"}, {"Mathematics", "C4"}, {"Physics", "C5"}, {"Chemistry", "C6"}, {"Biology", "C4"}},
            {{"P3"}, {"English Language", "C6"}, {"Mathematics", "D7"}, {"Physics", "C5"}, {"Chemistry", "C6"}, {"Biology", "C4"}, {"Economics", "B2"}},
        };
        LocalDate born = LocalDate.of(2003, 9, 12);
        it.db(() -> {
            for (String[][] o : olevel) {
                String j = jamb.get(o[0][0]);
                UUID att = UUID.randomUUID(), sit = UUID.randomUUID();
                jdbc.sql("""
                        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at)
                        VALUES (:id, :s, 'OLEVEL', :j || '-olevel.json', :j, 'EXACT', :c, now())
                        """).param("id", att).param("s", ses).param("j", j).param("c", cands.get(o[0][0])).update();
                jdbc.sql("""
                        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_year, exam_number, ord)
                        VALUES (:id, :att, :s, :j, 'WAEC', '2020', 'WAEC/' || :j, 1)
                        """).param("id", sit).param("att", att).param("s", ses).param("j", j).update();
                for (int g = 1; g < o.length; g++) {
                    jdbc.sql("INSERT INTO admissions.olevel_grade (sitting_id, subject, grade) VALUES (:sit, :sub, :g)")
                            .param("sit", sit).param("sub", o[g][0]).param("g", o[g][1]).update();
                }
            }
            jdbc.sql("""
                    INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at, payload)
                    VALUES (gen_random_uuid(), :s, 'DATE_OF_BIRTH', :j || '-dob.json', :j, 'EXACT', :c, now(), '{"dob": "12/09/2003"}'::jsonb)
                    """).param("s", ses).param("j", jamb.get("P3")).param("c", cands.get("P3")).update();
            // P2's A-Level, typed by hand: Chemistry A, Biology B, Physics C
            UUID aw = UUID.randomUUID();
            jdbc.sql("""
                    INSERT INTO admissions.de_award (id, session, jamb_key, basis, awarded_year, institution, recorded_by)
                    VALUES (:id, :s, :j, 'A_LEVEL', 2024, 'IT College', :w)
                    """).param("id", aw).param("s", ses).param("j", jamb.get("P2")).param("w", who).update();
            jdbc.sql("INSERT INTO admissions.de_award_subject (award_id, subject, grade, ord) VALUES (:a, 'Chemistry', 'A', 1), (:a, 'Biology', 'B', 2), (:a, 'Physics', 'C', 3)")
                    .param("a", aw).update();
            return null;
        });

        // ── 1 · DOCTOR OF PHARMACY is given its own Preliminary Fit rule; a rule that does not hold is refused, each by its name ──
        String fitPath = base + "/policy/programmes/" + PHARM + "/de-fit";
        ResponseEntity<Map> saved = it.call(academic, HttpMethod.PUT, fitPath, Map.of("rows", pharmacyRule()));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat(saved.getBody()).containsEntry("session", ses).containsEntry("policyState", "IN_FORCE");
        Map<String, Object> dflt = (Map<String, Object>) saved.getBody().get("default");
        assertThat(dflt).containsEntry("source", "BUILT_IN");
        assertThat(rowsOf(dflt)).extracting(r -> r.get("kind")).containsExactly("DEGREE", "UNIVERSITY_DIPLOMA", "HND", "ND", "NCE", "A_LEVEL");
        // "any discipline" is an absent list; "none" an empty one
        assertThat(rowsOf(dflt).get(0).get("coreDisciplines")).isNull();
        assertThat(rowsOf(dflt).get(0)).containsEntry("relevantMin", 3).containsEntry("partlyMin", 2).containsEntry("otherFit", "NOT_RELEVANT")
                .containsEntry("relatedDisciplines", List.of());
        assertThat(rowsOf(dflt).get(1)).containsEntry("coreDisciplines", List.of()).containsEntry("otherFit", "CHECK_MANUALLY");
        assertThat(rowsOf(dflt).get(5)).containsEntry("relevantPasses", 3).containsEntry("partlyPasses", 2);
        Map<String, List<Map<String, Object>>> classes = (Map<String, List<Map<String, Object>>>) saved.getBody().get("classes");
        assertThat(classes.keySet()).containsExactly("DEGREE", "UNIVERSITY_DIPLOMA", "HND", "ND", "A_LEVEL");
        assertThat(classes.get("DEGREE")).hasSize(5).first().satisfies(c -> assertThat(c).containsEntry("points", 5).containsEntry("name", "First Class"));
        assertThat(classes.get("A_LEVEL")).extracting(c -> c.get("name")).containsExactly("A", "B", "C", "D", "E");
        Map<String, Object> own = ownRule(saved.getBody(), PHARM);
        assertThat(own).as("Pharmacy's own rule").isNotNull().containsEntry("name", pharmacy);
        assertThat(rowsOf(own)).hasSize(6);
        assertThat(rowsOf(own).get(0)).containsEntry("kind", "DEGREE").containsEntry("relevantMin", 4).containsEntry("partlyMin", 3)
                .containsEntry("relatedPartlyMin", 3);
        assertThat(rowsOf(own).get(0).get("relatedRelevantMin")).isNull();
        assertThat((List<String>) rowsOf(own).get(0).get("coreDisciplines")).hasSize(10).startsWith("Chemistry", "Biochemistry");
        assertThat(rowsOf(own).get(5)).containsEntry("coreDisciplines", List.of("Biology/Zoology/Botany", "Chemistry", "Physics"))
                .containsEntry("relevantMin", 3).containsEntry("partlyMin", 1).containsEntry("relevantPasses", 3).containsEntry("partlyPasses", 3);
        assertThat((List<Map<String, Object>>) own.get("criteria")).anySatisfy(c -> assertThat(c)
                .containsEntry("qualification", "A'Level (GCE, IJMB, JUPEB) in Biology/Zoology/Botany, Chemistry and Physics")
                .containsEntry("rule", "3 passes at A–C = Relevant; 3 passes (A–E) = Partly relevant; fewer = Not relevant; F is a fail"));

        List<Map<String, Object>> five = pharmacyRule();
        five.remove(4);
        List<String> sixtyOne = new ArrayList<>();
        for (int i = 1; i <= 61; i++) {
            sixtyOne.add("Discipline " + i);
        }
        Object[][] refusals = {
            {five, "ADM_DE_FIT_KINDS"},
            {pharmacyRuleWith("DEGREE", "relevantMin", 6), "ADM_DE_FIT_RANGE"},
            {pharmacyRuleWith("DEGREE", "relevantMin", 2), "ADM_DE_FIT_ORDER"},
            {pharmacyRuleWith("A_LEVEL", "relevantPasses", null), "ADM_DE_FIT_PASSES"},
            {pharmacyRuleWith("DEGREE", "relatedDisciplines", sixtyOne), "ADM_DE_FIT_LIST"},
            {pharmacyRuleWith("A_LEVEL", "coreDisciplines", List.of()), "ADM_DE_FIT_LIST"},
            {pharmacyRuleWith("HND", "otherFit", "MAYBE"), "ADM_DE_FIT_OTHER"},
        };
        for (Object[] refusal : refusals) {
            ResponseEntity<Map> refused = it.call(academic, HttpMethod.PUT, fitPath, Map.of("rows", refusal[0]));
            assertThat(refused.getStatusCode().value()).as(refusal[1] + ": " + refused.getBody()).isEqualTo(422);
            assertThat(refused.getBody()).containsEntry("code", refusal[1]);
        }
        // the default states all six, always
        assertThat(it.call(academic, HttpMethod.PUT, base + "/policy/de-fit", Map.of("rows", List.of())).getBody()).containsEntry("code", "ADM_DE_FIT_KINDS");
        assertThat(it.call(ItSupport.token("records"), HttpMethod.PUT, fitPath, Map.of("rows", pharmacyRule())).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(academic, HttpMethod.PUT, base + "/policy/programmes/C99999/de-fit", Map.of("rows", pharmacyRule())).getStatusCode().value()).isEqualTo(404);
        // a refusal wrote nothing
        ResponseEntity<Map> fitNow = it.get(academic, base + "/policy/de-fit");
        assertThat(fitNow.getStatusCode().value()).isEqualTo(200);
        assertThat(rowsOf(ownRule(fitNow.getBody(), PHARM))).isEqualTo(rowsOf(own));

        // ── 2 · the workbook previewed: every row's outcome and problems, nothing kept ──
        String type = "JUPEB - A'Level";
        List<Map<String, Object>> sheet = new ArrayList<>();
        Map<String, Object> p1 = row(5, jamb.get("P1"), type, "JUPEB");
        p1.put("capsQualification", type);
        p1.put("capsGrade", 10);
        p1.put("hasFiveCredits", true);
        p1.put("isCleared", true);
        p1.put("status", "Not Admitted");
        p1.put("age", 20);
        p1.put("ageQualified", true);
        p1.put("admissionCategory", "Merit");
        p1.put("subjects", subjects("Biology", "C", "Chemistry", "C", "Physics", "C"));
        p1.put("year", 2026);
        p1.put("examNo", "78/JUPEB/0001");
        sheet.add(p1);
        Map<String, Object> p1Again = new LinkedHashMap<>(p1);
        p1Again.put("line", 6);
        sheet.add(p1Again);
        Map<String, Object> p2 = row(7, jamb.get("P2"), "1st Degree (Nigeria Universities)", "DEGREE");
        p2.put("hasFiveCredits", false);
        p2.put("isCleared", false);
        p2.put("discipline", "Biochemistry");
        p2.put("awardClass", "2nd Class Upper");
        sheet.add(p2);
        Map<String, Object> p3 = row(8, jamb.get("P3"), type, "JUPEB");
        p3.put("subjects", subjects("Biology", null, "Chemistry", null, "Physics", null));
        sheet.add(p3);
        Map<String, Object> p5 = row(9, jamb.get("P5"), "University Diploma", "UNIVERSITY_DIPLOMA");
        p5.put("discipline", "Law");
        p5.put("awardClass", "Credit");
        sheet.add(p5);
        Map<String, Object> u1 = row(10, jamb.get("U1"), type, "JUPEB");
        u1.put("subjects", subjects("Biology", "C", "Chemistry", "C", "Physics", "C"));
        sheet.add(u1);
        String notListed = y + "780009ZQ";
        Map<String, Object> x1 = row(11, notListed, type, "JUPEB");
        x1.put("subjects", subjects("Biology", "C", "Chemistry", "C", "Physics", "C"));
        sheet.add(x1);
        Map<String, Object> p6 = row(12, jamb.get("P6"), type, "JUPEB");
        p6.put("subjects", subjects("Biology", "B", "Chemistry", "B", "Physics", "B"));
        sheet.add(p6);
        Map<String, Object> p6Other = row(13, jamb.get("P6"), type, "JUPEB");
        p6Other.put("subjects", subjects("Biology", "C", "Chemistry", "C", "Physics", "C"));
        sheet.add(p6Other);
        String sha = "ab".repeat(32);
        Map<String, Object> file = new LinkedHashMap<>();
        file.put("filename", "it-de-candidates.xlsx");
        file.put("sha256", sha);
        file.put("programme", PHARM);
        file.put("rows", sheet);

        ResponseEntity<Map> preview = it.call(academic, HttpMethod.POST, base + "/de-candidates/upload/preview", file);
        assertThat(preview.getStatusCode().value()).as(String.valueOf(preview.getBody())).isEqualTo(200);
        assertThat(preview.getBody()).containsEntry("session", ses).containsEntry("programme", PHARM).containsEntry("preview", true).doesNotContainKey("uploadId");
        assertThat((Map<String, Object>) preview.getBody().get("counts")).containsEntry("read", 9).containsEntry("recorded", 4).containsEntry("unchanged", 0)
                .containsEntry("skipped", 4).containsEntry("repeated", 1).containsEntry("warnings", 2);
        List<Map<String, Object>> decided = rowsOf(preview.getBody());
        assertThat(decided).extracting(r -> r.get("line")).containsExactly(5, 6, 7, 8, 9, 10, 11, 12, 13);
        assertThat(decided).extracting(r -> r.get("outcome"))
                .containsExactly("RECORDED", "REPEATED", "RECORDED", "RECORDED", "RECORDED", "SKIPPED", "SKIPPED", "SKIPPED", "SKIPPED");
        assertThat(decided.get(0)).containsEntry("regNo", jamb.get("P1")).containsEntry("name", "ZZDECIT P1").containsEntry("programmeCode", PHARM)
                .containsEntry("programme", pharmacy).containsEntry("problems", List.of());
        assertThat(decided.get(1)).containsEntry("problems", List.of(Map.of("level", "WARNING", "text", "Repeated row: recorded once")));
        // a row on another programme's list is recorded, and said
        assertThat(decided.get(4)).containsEntry("programmeCode", LAW).containsEntry("programme", law).containsEntry("problems",
                List.of(Map.of("level", "WARNING", "text", "On JAMB's list under " + law + " (" + LAW + "), not " + pharmacy)));
        assertThat(decided.get(5)).containsEntry("problems",
                List.of(Map.of("level", "ERROR", "text", "On JAMB's list for " + ses + " as UTME, not Direct Entry")));
        assertThat(decided.get(6)).containsEntry("regNo", notListed).containsEntry("problems",
                List.of(Map.of("level", "ERROR", "text", "Not on JAMB's live Direct Entry list for " + ses)));
        assertThat(decided.get(6).get("name")).isNull();
        assertThat(decided.get(6).get("programmeCode")).isNull();
        for (int i = 7; i <= 8; i++) {
            assertThat(decided.get(i)).containsEntry("problems",
                    List.of(Map.of("level", "ERROR", "text", "REG NO. on lines 12, 13 with different details; none of them recorded")));
        }
        // a file past the limits is not read at all: more than 2,000 rows, no rows, a checksum or a programme that is not one, a row without its REG NO.
        Object[][] unread = {
            {"rows", java.util.Collections.nCopies(2001, x1)}, {"rows", List.of()}, {"sha256", "not-a-checksum"}, {"programme", "PHARMACY"},
            {"rows", List.of(row(5, " ", type, "JUPEB"))},
        };
        for (Object[] u : unread) {
            Map<String, Object> wrong = new LinkedHashMap<>(file);
            wrong.put((String) u[0], u[1]);
            ResponseEntity<Map> refused = it.call(academic, HttpMethod.POST, base + "/de-candidates/upload/preview", wrong);
            assertThat(refused.getStatusCode().value()).as(u[0] + ": " + refused.getBody()).isEqualTo(400);
            assertThat(refused.getBody()).containsEntry("code", "VALIDATION_FAILED");
        }
        ResponseEntity<Map> before = it.get(academic, base + "/de-candidates?programme=" + PHARM);
        assertThat(before.getStatusCode().value()).as(String.valueOf(before.getBody())).isEqualTo(200);
        assertThat(rowsOf(before.getBody())).filteredOn(r -> "ZZDECIT P1".equals(r.get("name"))).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("qualificationType", "Not recorded").containsEntry("fit", "Check manually"));
        assertThat(it.db(() -> jdbc.sql("""
                SELECT (SELECT count(*) FROM admissions.de_upload WHERE session = :s) + (SELECT count(*) FROM admissions.de_caps_value WHERE session = :s)
                     + (SELECT count(*) FROM admissions.de_award WHERE session = :s AND source = 'UPLOAD')
                """).param("s", ses).query(Long.class).single())).as("the preview kept nothing").isZero();

        // ── 3 · recorded; and the same file again changes nothing ──
        ResponseEntity<Map> recorded = it.call(academic, HttpMethod.POST, base + "/de-candidates/upload", file);
        assertThat(recorded.getStatusCode().value()).as(String.valueOf(recorded.getBody())).isEqualTo(200);
        assertThat(recorded.getBody()).containsEntry("preview", false);
        assertThat((Map<String, Object>) recorded.getBody().get("counts")).containsEntry("read", 9).containsEntry("recorded", 4).containsEntry("unchanged", 0)
                .containsEntry("skipped", 4).containsEntry("repeated", 1);
        // the preview's outcomes are the commit's
        assertThat(rowsOf(recorded.getBody())).isEqualTo(decided);
        String uploadId = (String) recorded.getBody().get("uploadId");
        assertThat(uploadId).isNotNull();
        Map<String, Object> upload = it.db(() -> jdbc.sql("""
                SELECT u.id::text AS id, u.filename, encode(u.file_sha256, 'hex') AS sha, u.programme_code, u.rows_read, u.rows_recorded, u.rows_unchanged,
                       u.rows_skipped, u.rows_repeated, u.uploaded_by::text AS uploaded_by, u.uploaded_office
                  FROM admissions.de_upload u WHERE u.session = :s
                """).param("s", ses).query().singleRow());
        assertThat(upload).containsEntry("id", uploadId).containsEntry("filename", "it-de-candidates.xlsx").containsEntry("sha", sha)
                .containsEntry("programme_code", PHARM).containsEntry("rows_read", 9).containsEntry("rows_recorded", 4).containsEntry("rows_unchanged", 0)
                .containsEntry("rows_skipped", 4).containsEntry("rows_repeated", 1).containsEntry("uploaded_by", who.toString())
                .containsEntry("uploaded_office", "academic");
        // CAPS's own values kept as the file read them: cleared for P1, not for P2
        assertThat(it.db(() -> jdbc.sql("""
                SELECT string_agg(right(v.jamb_key, 3) || ':' || coalesce(v.is_cleared::text, '-') || ':' || coalesce(v.has_five_credits::text, '-')
                                  || ':' || coalesce(v.caps_grade::text, '-'), ' ' ORDER BY v.jamb_key)
                  FROM admissions.de_caps_value v WHERE v.session = :s
                """).param("s", ses).query(String.class).single())).isEqualTo("1ZQ:true:true:10 2ZQ:false:false:-");
        // the upload's awards are its own; P2's A-Level typed by hand stays beside the uploaded degree
        assertThat(it.db(() -> jdbc.sql("""
                SELECT string_agg(right(d.jamb_key, 3) || ':' || d.basis || ':' || d.source, ' ' ORDER BY d.jamb_key, d.basis)
                  FROM admissions.de_award d WHERE d.session = :s
                """).param("s", ses).query(String.class).single()))
                .isEqualTo("1ZQ:JUPEB:UPLOAD 2ZQ:A_LEVEL:MANUAL 2ZQ:DEGREE:UPLOAD 3ZQ:JUPEB:UPLOAD 5ZQ:UNIVERSITY_DIPLOMA:UPLOAD");

        ResponseEntity<Map> again = it.call(academic, HttpMethod.POST, base + "/de-candidates/upload", file);
        assertThat(again.getStatusCode().value()).as(String.valueOf(again.getBody())).isEqualTo(200);
        assertThat(again.getBody()).doesNotContainKey("uploadId");
        assertThat((Map<String, Object>) again.getBody().get("counts")).containsEntry("recorded", 0).containsEntry("unchanged", 4)
                .containsEntry("skipped", 4).containsEntry("repeated", 1);
        assertThat(it.db(() -> jdbc.sql("SELECT count(*) || ':' || max(rows_repeated) FROM admissions.de_upload WHERE session = :s")
                .param("s", ses).query(String.class).single())).isEqualTo("1:1");

        // ── 4 · the sheet of DOCTOR OF PHARMACY: everyone on its list, by score then name ──
        int age = Period.between(born, LocalDate.now(ZoneId.of("Africa/Lagos"))).getYears();
        ResponseEntity<Map> got = it.get(academic, base + "/de-candidates?programme=" + PHARM);
        assertThat(got.getStatusCode().value()).as(String.valueOf(got.getBody())).isEqualTo(200);
        assertThat(got.getBody()).containsEntry("session", ses).containsEntry("programme", Map.of("code", PHARM, "name", pharmacy))
                .containsEntry("asAt", LocalDate.now(ZoneId.of("Africa/Lagos")).toString())
                .containsEntry("policy", Map.of("state", "IN_FORCE", "instrument", "IT CAC/DEC/1"));
        assertThat((Map<String, Object>) got.getBody().get("olevel"))
                .containsEntry("subjects", List.of("English Language", "Mathematics", "Physics", "Chemistry", "Biology"))
                .containsEntry("credits", 5).containsEntry("sittings", 2).containsEntry("required", List.of("English Language", "Mathematics"));
        Map<String, Object> fit = (Map<String, Object>) got.getBody().get("fit");
        assertThat(fit).containsEntry("source", "PROGRAMME");
        assertThat((List<Map<String, Object>>) fit.get("criteria")).isEqualTo(own.get("criteria"));
        List<Map<String, Object>> rows = rowsOf(got.getBody());
        assertThat(rows).extracting(r -> r.get("name")).containsExactly("ZZDECIT P2", "ZZDECIT P1", "ZZDECIT P3", "ZZDECIT P4", "ZZDECIT P6");
        assertThat(rows).extracting(r -> r.get("rank")).containsExactly(1, 2, 3, 4, 5);
        // S/N is the place on JAMB's list, alphabetical, whatever the rank
        assertThat(rows).extracting(r -> r.get("listNo")).containsExactly(2, 1, 3, 4, 5);
        assertThat(rows).extracting(r -> r.get("registered")).containsExactly(false, true, true, false, false);

        // P2: the A-Level typed by hand counts (81.25 over the uploaded degree's 80.00), under Pharmacy's own rule
        assertThat(rows.get(0)).containsEntry("regNo", jamb.get("P2")).containsEntry("basis", "A_LEVEL").containsEntry("qualificationType", "GCE A'Level")
                .containsEntry("points", 13).containsEntry("maxPoints", 16).containsEntry("score", 81.25).containsEntry("fit", "Relevant")
                .containsEntry("reason", "Passed Biology, Chemistry and Physics (B, A, C); points 13")
                .containsEntry("hasFiveCredits", false).containsEntry("isCleared", "NOT CLEARED").containsEntry("status", "Not Admitted")
                .containsEntry("institution", "IT College").containsEntry("year", 2024)
                .containsEntry("otherNotes", "O'Level 5 credits not confirmed; Candidate NOT CLEARED in CAPS; Not registered on the portal; "
                        + "Also recorded: 1st Degree (Nigeria Universities) (80.00%)")
                .containsEntry("olevelCheck", "No O'Level on record: candidate must upload/verify results").containsEntry("olevelCheckKind", "NONE");
        for (String absent : List.of("capsQualification", "capsGrade", "age", "ageQualified", "admissionCategory", "examNo", "olevelResults", "olevelSittings")) {
            assertThat(rows.get(0).get(absent)).as(absent).isNull();
        }

        // P1: what the file said of the candidate, the JUPEB's score, the O'Level the portal holds — and every key of a full row
        Map<String, Object> one = rows.get(1);
        assertThat(one.keySet()).containsExactlyInAnyOrder(ROW_KEYS);
        assertThat(one).containsEntry("regNo", jamb.get("P1")).containsEntry("state", "Benue").containsEntry("lga", "Makurdi").containsEntry("sex", "F")
                .containsEntry("capsQualification", type).containsEntry("capsGrade", 10).containsEntry("hasFiveCredits", true)
                .containsEntry("isCleared", "CLEARED").containsEntry("status", "Not Admitted").containsEntry("age", 20).containsEntry("ageQualified", true)
                .containsEntry("admissionCategory", "Merit").containsEntry("basis", "JUPEB").containsEntry("qualificationType", type)
                .containsEntry("discipline", "Biology / Chemistry / Physics").containsEntry("grades", "Biology: C; Chemistry: C; Physics: C")
                .containsEntry("points", 10).containsEntry("maxPoints", 16).containsEntry("score", 62.5).containsEntry("classPoints", "10")
                .containsEntry("institution", "Not shown in CAPS").containsEntry("year", 2026).containsEntry("examNo", "78/JUPEB/0001")
                .containsEntry("fit", "Relevant").containsEntry("reason", "Passed Biology, Chemistry and Physics (C, C, C); points 10")
                .containsEntry("olevelResults", "Biology: C4; Chemistry: C6; English Language: B3; Mathematics: C4; Physics: C5")
                .containsEntry("olevelSittings", "WAEC 2020 (WAEC/" + jamb.get("P1") + ")").containsEntry("sittings", 1)
                .containsEntry("keyCredits", 5).containsEntry("keyOf", 5).containsEntry("totalCredits", 5)
                .containsEntry("olevelCheck", "Credits in English Language and Mathematics (1 sitting)").containsEntry("olevelCheckKind", "PASS");
        assertThat((List<Map<String, Object>>) one.get("olevelGrades")).containsExactly(
                Map.of("subject", "English Language", "grade", "B3", "credit", true), Map.of("subject", "Mathematics", "grade", "C4", "credit", true),
                Map.of("subject", "Physics", "grade", "C5", "credit", true), Map.of("subject", "Chemistry", "grade", "C6", "credit", true),
                Map.of("subject", "Biology", "grade", "C4", "credit", true));

        // P3: subjects without grades — no score, after the scored; the age counted from the date of birth
        assertThat(rows.get(2)).containsEntry("basis", "JUPEB").containsEntry("maxPoints", 16).containsEntry("fit", "Check manually")
                .containsEntry("reason", "Biology/Chemistry/Physics combination is right, but no grades released in CAPS yet")
                .containsEntry("grades", "Biology: —; Chemistry: —; Physics: —").containsEntry("age", age).containsEntry("hasFiveCredits", true)
                .containsEntry("olevelCheck", "No credit in Mathematics").containsEntry("olevelCheckKind", "PROBLEM")
                .containsEntry("keyCredits", 4).containsEntry("keyOf", 5).containsEntry("totalCredits", 5);
        assertThat(rows.get(2).get("score")).isNull();
        assertThat(rows.get(2).get("points")).isNull();
        assertThat(rows.get(2).get("otherNotes")).isNull();
        assertThat(((List<Map<String, Object>>) rows.get(2).get("olevelGrades")).get(1)).containsEntry("subject", "Mathematics").containsEntry("grade", "D7")
                .containsEntry("credit", false);

        // P4 and P6: nothing recorded, no O'Level — last, by name
        for (int i = 3; i <= 4; i++) {
            assertThat(rows.get(i)).containsEntry("qualificationType", "Not recorded").containsEntry("fit", "Check manually")
                    .containsEntry("reason", "No qualification recorded").containsEntry("isCleared", "CLEARED").containsEntry("hasFiveCredits", false)
                    .containsEntry("otherNotes", "O'Level 5 credits not confirmed; Not registered on the portal")
                    .containsEntry("olevelCheck", "No O'Level on record: candidate must upload/verify results").containsEntry("olevelCheckKind", "NONE")
                    .containsEntry("sittings", 0).containsEntry("keyCredits", 0).containsEntry("keyOf", 5);
            for (String absent : List.of("basis", "discipline", "grades", "points", "maxPoints", "score", "classPoints", "institution", "year", "examNo")) {
                assertThat(rows.get(i).get(absent)).as(absent).isNull();
            }
            // a subject column each, without a grade
            assertThat((List<Map<String, Object>>) rows.get(i).get("olevelGrades")).hasSize(5).first()
                    .satisfies(g -> assertThat(g).containsEntry("subject", "English Language").containsEntry("credit", false).doesNotContainKey("grade"));
        }

        // ── 5 · LL.B (LAW) follows the University's default (none set for the session: the built-in one) ──
        ResponseEntity<Map> lawSheet = it.get(academic, base + "/de-candidates?programme=" + LAW);
        assertThat(lawSheet.getStatusCode().value()).as(String.valueOf(lawSheet.getBody())).isEqualTo(200);
        assertThat((Map<String, Object>) lawSheet.getBody().get("fit")).containsEntry("source", "BUILT_IN");
        assertThat((Map<String, Object>) lawSheet.getBody().get("olevel")).containsEntry("subjects", List.of("English Language", "Mathematics"));
        assertThat(rowsOf(lawSheet.getBody())).singleElement().satisfies(r -> assertThat(r).containsEntry("name", "ZZDECIT P5")
                .containsEntry("basis", "UNIVERSITY_DIPLOMA").containsEntry("qualificationType", "University Diploma").containsEntry("discipline", "Law")
                .containsEntry("classPoints", "Credit").containsEntry("grades", "Law: Credit").containsEntry("points", 3).containsEntry("maxPoints", 4)
                .containsEntry("score", 75.0).containsEntry("fit", "Relevant")
                .containsEntry("reason", "Diploma in Law at Credit; directly related to the programme").containsEntry("registered", true));
        // a University Diploma has no subject rows, and is on file all the same
        ResponseEntity<Map> screening = it.get(academic, b -> b.path("/api/v1/admissions/de-screening").queryParam("session", ses).queryParam("programme", LAW).build());
        assertThat(screening.getStatusCode().value()).as(String.valueOf(screening.getBody())).isEqualTo(200);
        assertThat(rowsOf(screening.getBody())).singleElement()
                .satisfies(r -> assertThat(r).containsEntry("jamb_reg_no", jamb.get("P5")).containsEntry("has_data", true));

        // ── 6 · the programmes on JAMB's live Direct Entry list; what is not a programme; the programme left out ──
        ResponseEntity<Map> listed = it.get(academic, base + "/de-candidates/programmes");
        assertThat(listed.getStatusCode().value()).as(String.valueOf(listed.getBody())).isEqualTo(200);
        assertThat(listed.getBody()).containsEntry("session", ses);
        assertThat((List<Map<String, Object>>) listed.getBody().get("programmes")).containsExactly(
                Map.of("code", PHARM, "name", pharmacy, "onList", 5, "registered", 2, "recorded", 3),
                Map.of("code", LAW, "name", law, "onList", 1, "registered", 1, "recorded", 1));
        assertThat(ownRule(it.get(academic, base + "/policy/de-fit").getBody(), PHARM)).isNotNull();
        assertThat(it.get(academic, base + "/de-candidates?programme=C99999").getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(academic, base + "/de-candidates?programme=PHARMACY").getStatusCode().value()).isEqualTo(404);
        assertThat(it.get(academic, base + "/de-candidates").getStatusCode().value()).isEqualTo(400);

        // ── 7 · the next session begins from this one, with the fit rules ──
        String next = "/api/v1/admissions/sessions/" + (y + 1) + "/" + (y + 2);
        ResponseEntity<Map> begun = it.call(academic, HttpMethod.POST, next + "/policy/start-from/" + y + "/" + (y + 1), null);
        assertThat(begun.getStatusCode().value()).as(String.valueOf(begun.getBody())).isEqualTo(200);
        ResponseEntity<Map> nextFit = it.get(academic, next + "/policy/de-fit");
        assertThat(nextFit.getStatusCode().value()).as(String.valueOf(nextFit.getBody())).isEqualTo(200);
        assertThat(nextFit.getBody()).containsEntry("policyState", "DRAFT");
        assertThat(rowsOf(ownRule(nextFit.getBody(), PHARM))).isEqualTo(rowsOf(own));
        assertThat(it.db(() -> jdbc.sql("""
                SELECT count(*) || ':' || count(*) FILTER (WHERE f.set_by = :w AND f.set_office = 'academic')
                  FROM admissions.de_fit_rule f JOIN admissions.session_policy p ON p.id = f.policy_id WHERE p.session = :s
                """).param("w", who).param("s", (y + 1) + "/" + (y + 2)).query(String.class).single())).isEqualTo("6:6");

        // ── 8 · typed by hand: a degree by its discipline and class, an NCE's double major, a subject typed twice once ──
        String awards = "/api/v1/admissions/de-awards";
        Map<String, Object> degree = new LinkedHashMap<>();
        degree.put("session", ses);
        degree.put("jambKey", jamb.get("P4"));
        degree.put("basis", "DEGREE");
        degree.put("awardedYear", 2023);
        degree.put("institution", null);
        degree.put("subjects", List.of());
        degree.put("discipline", "Chemistry");
        degree.put("awardClass", "2nd Class Upper");
        degree.put("examNo", "78/DEG/0004");
        ResponseEntity<List> typed = it.callList(academic, HttpMethod.POST, awards, degree);
        assertThat(typed.getStatusCode().value()).as(String.valueOf(typed.getBody())).isEqualTo(200);
        ResponseEntity<List> onFile = it.getList(academic, awards + "?session=" + ses + "&jambKey=" + jamb.get("P4"));
        assertThat(onFile.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) onFile.getBody()).singleElement().satisfies(a -> assertThat(a).containsEntry("basis", "DEGREE")
                .containsEntry("discipline", "Chemistry").containsEntry("award_class", "2nd Class Upper").containsEntry("exam_no", "78/DEG/0004")
                .containsEntry("source", "MANUAL").containsEntry("awarded_year", 2023).containsEntry("subjects", List.of()));
        Map<String, Object> nothing = new LinkedHashMap<>(degree);
        nothing.put("discipline", " ");
        nothing.put("awardClass", null);
        ResponseEntity<Map> empty = it.call(academic, HttpMethod.POST, awards, nothing);
        assertThat(empty.getStatusCode().value()).as(String.valueOf(empty.getBody())).isEqualTo(422);
        assertThat(empty.getBody()).containsEntry("code", "DE_AWARD_EMPTY");
        Map<String, Object> nce = new LinkedHashMap<>();
        nce.put("session", ses);
        nce.put("jambKey", jamb.get("P6"));
        nce.put("basis", "NCE");
        nce.put("subjects", subjects("English", "Merit", "English", "Merit", "Education", "Merit"));
        ResponseEntity<List> nceTyped = it.callList(academic, HttpMethod.POST, awards, nce);
        assertThat(nceTyped.getStatusCode().value()).as(String.valueOf(nceTyped.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) nceTyped.getBody()).singleElement().satisfies(a -> assertThat(a).containsEntry("basis", "NCE")
                .containsEntry("source", "MANUAL").containsEntry("subjects", List.of(Map.of("subject", "English", "grade", "Merit"),
                        Map.of("subject", "English", "grade", "Merit"), Map.of("subject", "Education", "grade", "Merit"))));
        Map<String, Object> jupeb = new LinkedHashMap<>(nce);
        jupeb.put("basis", "JUPEB");
        jupeb.put("subjects", subjects("Biology", "C", "biology", "B"));
        ResponseEntity<List> jupebTyped = it.callList(academic, HttpMethod.POST, awards, jupeb);
        assertThat(jupebTyped.getStatusCode().value()).as(String.valueOf(jupebTyped.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) jupebTyped.getBody()).extracting(a -> a.get("basis")).containsExactly("JUPEB", "NCE");
        assertThat(((List<Map<String, Object>>) jupebTyped.getBody()).get(0)).containsEntry("subjects", List.of(Map.of("subject", "Biology", "grade", "C")));
        // an A'Level without a subject, and a type only an upload records, are not typed
        Map<String, Object> bare = new LinkedHashMap<>(nce);
        bare.put("basis", "IJMB");
        bare.put("subjects", List.of());
        assertThat(it.call(academic, HttpMethod.POST, awards, bare).getBody()).containsEntry("code", "DE_AWARD_EMPTY");
        Map<String, Object> notStated = new LinkedHashMap<>(nce);
        notStated.put("basis", "NOT_STATED");
        assertThat(it.call(academic, HttpMethod.POST, awards, notStated).getStatusCode().value()).isEqualTo(400);
        // and the sheet reads what was typed: P4's degree (80.00, a core discipline), P6's NCE (9 of 15) above its one JUPEB subject
        List<Map<String, Object>> after = rowsOf(it.get(academic, base + "/de-candidates?programme=" + PHARM).getBody());
        assertThat(after).extracting(r -> r.get("name")).containsExactly("ZZDECIT P2", "ZZDECIT P4", "ZZDECIT P1", "ZZDECIT P6", "ZZDECIT P3");
        assertThat(after.get(1)).containsEntry("qualificationType", "1st Degree (Nigeria Universities)").containsEntry("discipline", "Chemistry")
                .containsEntry("classPoints", "2nd Class Upper").containsEntry("points", 4).containsEntry("maxPoints", 5).containsEntry("score", 80.0)
                .containsEntry("fit", "Relevant").containsEntry("reason", "Degree in Chemistry (2nd Class Upper): a core discipline for " + pharmacy + " DE")
                .containsEntry("examNo", "78/DEG/0004");
        assertThat(after.get(3)).containsEntry("basis", "NCE").containsEntry("discipline", "English / Education").containsEntry("points", 9)
                .containsEntry("maxPoints", 15).containsEntry("score", 60.0).containsEntry("fit", "Check manually")
                .containsEntry("otherNotes", "O'Level 5 credits not confirmed; Not registered on the portal; Also recorded: JUPEB - A'Level (25.00%)");

        // ── 9 · a candidate who has not registered, found by REG NO. as typed ──
        ResponseEntity<Map> found = it.get(academic, b -> b.path(base + "/de-candidates/lookup").queryParam("regNo", "  " + jamb.get("P6").toLowerCase() + " ").build());
        assertThat(found.getStatusCode().value()).as(String.valueOf(found.getBody())).isEqualTo(200);
        assertThat(found.getBody()).isEqualTo(Map.of("jambKey", jamb.get("P6"), "regNo", jamb.get("P6"), "name", "ZZDECIT P6", "programmeCode", PHARM,
                "programme", pharmacy, "registered", false));
        assertThat(it.get(academic, base + "/de-candidates/lookup?regNo=" + jamb.get("P5")).getBody()).containsEntry("registered", true)
                .containsEntry("programmeCode", LAW);
        assertThat(it.get(academic, base + "/de-candidates/lookup?regNo=" + notListed).getStatusCode().value()).isEqualTo(404);
        // on the list for UTME: not a Direct Entry candidate
        assertThat(it.get(academic, base + "/de-candidates/lookup?regNo=" + jamb.get("U1")).getStatusCode().value()).isEqualTo(404);

        // ── 10 · the offices that do not upload, and those that do not read ──
        String deputy = ItSupport.token("dregistrar");
        assertThat(it.call(deputy, HttpMethod.POST, base + "/de-candidates/upload", file).getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(deputy, HttpMethod.POST, base + "/de-candidates/upload/preview", file).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(deputy, base + "/de-candidates?programme=" + PHARM).getStatusCode().value()).isEqualTo(200);
        String lecturer = ItSupport.token("lecturer");
        assertThat(it.get(lecturer, base + "/de-candidates?programme=" + PHARM).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, base + "/de-candidates/programmes").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, base + "/de-candidates/lookup?regNo=" + jamb.get("P6")).getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(lecturer, base + "/policy/de-fit").getStatusCode().value()).isEqualTo(403);
        // one who holds the Academic Office but acts as another office does not upload as that office
        ResponseEntity<Map> asDeputy = it.callWith(TestTokens.token(who, List.of("academic", "dregistrar")), HttpMethod.POST, base + "/de-candidates/upload",
                file, Map.of("X-Active-Office", "dregistrar"));
        assertThat(asDeputy.getStatusCode().value()).as(String.valueOf(asDeputy.getBody())).isEqualTo(422);
        assertThat(asDeputy.getBody()).containsEntry("code", "ADM_DE_UPLOAD_OFFICE");

        // ── 11 · the University's default saved for the session; Pharmacy back to it; settings a session does not have ──
        List<Map<String, Object>> universityDefault = pharmacyRule();
        universityDefault.set(0, rule("DEGREE", null, 3, 2, List.of(), null, null, "NOT_RELEVANT", null, null));
        universityDefault.set(5, rule("A_LEVEL", null, 1, 1, List.of(), null, null, "NOT_RELEVANT", 3, 2));
        ResponseEntity<Map> defaultSaved = it.call(academic, HttpMethod.PUT, base + "/policy/de-fit", Map.of("rows", universityDefault));
        assertThat(defaultSaved.getStatusCode().value()).as(String.valueOf(defaultSaved.getBody())).isEqualTo(200);
        Map<String, Object> savedDefault = (Map<String, Object>) defaultSaved.getBody().get("default");
        assertThat(savedDefault).containsEntry("source", "DEFAULT");
        assertThat(rowsOf(savedDefault).get(0).get("coreDisciplines")).isNull();
        assertThat(rowsOf(savedDefault).get(2)).containsEntry("coreDisciplines", List.of("Pharmaceutical Technology/Pharmacy Technician"));
        assertThat((List<Map<String, Object>>) savedDefault.get("criteria")).first().satisfies(c -> assertThat(c)
                .containsEntry("qualification", "1st Degree (Nigerian or foreign), any discipline")
                .containsEntry("rule", "First Class/2nd Class Upper/2nd Class Lower = Relevant; 3rd Class = Partly relevant; Pass = Not relevant"));
        assertThat(ownRule(defaultSaved.getBody(), PHARM)).isNotNull();
        ResponseEntity<Map> back = it.call(academic, HttpMethod.PUT, fitPath, Map.of("rows", List.of()));
        assertThat(back.getStatusCode().value()).as(String.valueOf(back.getBody())).isEqualTo(200);
        assertThat((List<?>) back.getBody().get("programmes")).isEmpty();
        assertThat((Map<String, Object>) it.get(academic, base + "/de-candidates?programme=" + PHARM).getBody().get("fit")).containsEntry("source", "DEFAULT");
        assertThat(it.get(academic, "/api/v1/admissions/sessions/1801/1802/policy/de-fit").getStatusCode().value()).isEqualTo(404);
        // the sheet of a session without settings is still made: nobody on its list, the built-in rule, English Language and Mathematics
        ResponseEntity<Map> bare1801 = it.get(academic, "/api/v1/admissions/sessions/1801/1802/de-candidates?programme=" + PHARM);
        assertThat(bare1801.getStatusCode().value()).as(String.valueOf(bare1801.getBody())).isEqualTo(200);
        assertThat(bare1801.getBody()).containsEntry("rows", List.of()).doesNotContainKey("policy");
        assertThat((Map<String, Object>) bare1801.getBody().get("fit")).containsEntry("source", "BUILT_IN");
        assertThat((Map<String, Object>) bare1801.getBody().get("olevel")).containsEntry("subjects", List.of("English Language", "Mathematics"))
                .containsEntry("credits", 5).containsEntry("sittings", 2).containsEntry("required", List.of("English Language", "Mathematics"));
        assertThat(it.call(academic, HttpMethod.PUT, "/api/v1/admissions/sessions/1801/1802/policy/de-fit", Map.of("rows", universityDefault)).getStatusCode().value())
                .isEqualTo(404);
    }
}
