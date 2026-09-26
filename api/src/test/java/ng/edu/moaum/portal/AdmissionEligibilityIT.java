package ng.edu.moaum.portal;

import static org.assertj.core.api.Assertions.assertThat;

import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.UUID;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.MethodOrderer;
import org.junit.jupiter.api.Order;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestMethodOrder;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.HttpMethod;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * The automatic admission course suggestion engine (V266), end to end, against the
 * session's own admission settings and nothing hard-coded:
 *
 * <ol>
 *   <li>a candidate who meets every rule of the applied programme reads ELIGIBLE, and no alternative is searched;</li>
 *   <li>one who fails it reads NOT ELIGIBLE with the failed requirement named, and the programmes the same record
 *       qualifies for are listed, the eligible first;</li>
 *   <li>every verdict is explained check by check — requirement, candidate, result;</li>
 *   <li>a record that qualifies for nothing says so, and a closed programme or one without a rule is never suggested;</li>
 *   <li>two sittings are combined when the rule allows two and refused when it allows one — and changing that rule
 *       moves the policy's version so the next reading is re-evaluated by itself;</li>
 *   <li>an equivalence stated by the Secretariat is honoured; none is invented;</li>
 *   <li>the officers' register is searched and filtered on the server, with the statistics;</li>
 *   <li>the applicant sees only their own verdict and the programmes they qualify for, may ask for one of those and no
 *       other, and the Office's approval changes the programme and re-evaluates;</li>
 *   <li>a change to the record marks the evaluation stale and it is re-read on the next open;</li>
 *   <li>every evaluation, recommendation, viewing and decision is on the trail; an office without the door is refused.</li>
 * </ol>
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
@TestMethodOrder(MethodOrderer.OrderAnnotation.class)
class AdmissionEligibilityIT {

    static final String SESSION = "2086/2087";
    static final String PATH = "/api/v1/admissions/sessions/2086/2087";
    static final String CS = "C00023", ACC = "C00019", ECO = "C00024", MBBS = "C00061";
    static final UUID POLICY = UUID.fromString("e1191b1e-0000-4000-8000-000000002086");

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");
    final String registrar = ItSupport.token("registrar");
    final String housing = ItSupport.token("housing");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
        it.session(SESSION, 2086);
        settings();
    }

    /* ── the session's admission settings: the only source of every requirement ── */
    void settings() {
        it.db(() -> {
            jdbc.sql("""
                    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, state, instrument, in_force)
                    VALUES (:id, :s, 1200, 70, 30, 'IN_FORCE', 'Senate minute EligibilityIT/1', tstzrange(now(), NULL)) ON CONFLICT DO NOTHING
                    """).param("id", POLICY).param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.load_cutoff (session, cutoff) VALUES (:s, 140) ON CONFLICT (session) DO UPDATE SET cutoff = 140").param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff) SELECT :id, code, 100, 150 FROM ref.faculty ON CONFLICT DO NOTHING").param("id", POLICY).update();
            // Computer Science 200 · Accounting 180 · Economics 160 · MBBS stated but closed; every other programme has no rule this session
            for (String[] r : new String[][] {{CS, "200"}, {ACC, "180"}, {ECO, "160"}, {MBBS, "250"}}) {
                jdbc.sql("""
                        INSERT INTO admissions.programme_rule (policy_id, programme_code, cutoff, quota, olevel_text, utme_text, de_text, olevel_credits, olevel_sittings)
                        VALUES (:id, :c, :k, 50, 'Five credits (test)', 'As configured (test)', 'A-Level (test)', 5, 2) ON CONFLICT (policy_id, programme_code) DO UPDATE SET cutoff = EXCLUDED.cutoff, olevel_sittings = 2
                        """).param("id", POLICY).param("c", r[0]).param("k", Integer.parseInt(r[1])).update();
            }
            jdbc.sql("INSERT INTO admissions.programme_closed (policy_id, programme_code, reason) VALUES (:id, :c, 'Not admitting this session (test)') ON CONFLICT DO NOTHING").param("id", POLICY).param("c", MBBS).update();
            // the subject rules, stated fresh each run
            jdbc.sql("DELETE FROM admissions.rule_subject WHERE group_id IN (SELECT id FROM admissions.rule_subject_group WHERE policy_id = :id)").param("id", POLICY).update();
            jdbc.sql("DELETE FROM admissions.rule_subject_group WHERE policy_id = :id").param("id", POLICY).update();
            group(CS, "OLEVEL_REQUIRED", "C6", "Physics", "Chemistry");
            group(CS, "UTME", null, "Physics", "Chemistry/Biology");
            group(ACC, "OLEVEL_REQUIRED", "C6", "Economics/Accounting");
            group(ACC, "UTME", null, "Economics");
            group(ECO, "OLEVEL_REQUIRED", "C6", "Economics");
            group(ECO, "UTME", null, "Economics");
            group(MBBS, "OLEVEL_REQUIRED", "C6", "Physics", "Chemistry", "Biology");
            // no equivalence stands at the start; the test states one later
            jdbc.sql("DELETE FROM admissions.subject_equivalence WHERE policy_id = :id").param("id", POLICY).update();
            jdbc.sql("UPDATE admissions.programme_rule SET additional_screening = NULL WHERE policy_id = :id").param("id", POLICY).update();
            return null;
        });
    }

    void group(String programme, String scope, String minGrade, String... items) {
        UUID g = UUID.randomUUID();
        jdbc.sql("INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose, min_grade) VALUES (:g, :p, :c, :s, 1, :m)")
                .param("g", g).param("p", POLICY).param("c", programme).param("s", scope).param("m", minGrade, java.sql.Types.VARCHAR).update();
        for (String i : items) {
            jdbc.sql("INSERT INTO admissions.rule_subject (group_id, subject) VALUES (:g, :s)").param("g", g).param("s", i).update();
        }
    }

    /** a submitted applicant: the candidate on the CAPS list with a score and four UTME subjects, an account, an application, O'Level sittings as JAMB sent them */
    record Applicant(UUID app, UUID account, UUID candidate, String jamb, String surname) { }

    @SafeVarargs
    final Applicant applicant(String programme, int score, List<String> utme, List<Map<String, String>>... sittings) {
        int n = new Random().nextInt(90_000_000) + 10_000_000;
        String jamb = "2086" + n + "EL";
        String surname = "ZZELIG-" + n;
        return it.db(() -> {
            UUID cand = UUID.randomUUID(), acct = UUID.randomUUID(), appId = UUID.randomUUID(), batch = UUID.randomUUID();
            jdbc.sql("INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state) "
                    + "VALUES (:id, :s, :j, :sn, 'Test Person', (SELECT name FROM ref.programme WHERE code = :p), 'UTME', 100, 'PROPOSED')")
                    .param("id", cand).param("s", SESSION).param("j", jamb).param("sn", surname).param("p", programme).update();
            jdbc.sql("INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash) "
                    + "VALUES (:id, :s, :c, :k, :e, '08030000000', crypt('x', gen_salt('bf', 12)))")
                    .param("id", acct).param("s", SESSION).param("c", cand).param("k", jamb).param("e", jamb.toLowerCase() + "@example.com").update();
            jdbc.sql("INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at) VALUES (:id, :a, :c, :s, :no, now(), now())")
                    .param("id", appId).param("a", acct).param("c", cand).param("s", SESSION).param("no", "APP/86/" + String.format("%06d", n % 1_000_000)).update();
            jdbc.sql("INSERT INTO admissions.caps_batch (id, session, source, filename, file_sha256, rows_read, list_kind, downloaded_on, uploaded_by, uploaded_office, committed_at) "
                    + "VALUES (:id, :s, 'CAPS_DOWNLOAD', 'elig.xlsx', decode(md5(:id::text), 'hex'), 1, 'UTME', current_date, gen_random_uuid(), 'academic', now())")
                    .param("id", batch).param("s", SESSION).update();
            jdbc.sql("INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode) "
                    + "VALUES (gen_random_uuid(), :b, :s, :j, jsonb_build_object('Subject1', :s1, 'Subject2', :s2, 'Subject3', :s3, 'Subject4', :s4), :sn, 'Test Person', :p, :agg, 'UTME')")
                    .param("b", batch).param("s", SESSION).param("j", jamb).param("s1", utme.get(0)).param("s2", utme.get(1)).param("s3", utme.get(2)).param("s4", utme.get(3))
                    .param("sn", surname).param("p", programme).param("agg", score).update();
            int ord = 0;
            for (List<Map<String, String>> sitting : sittings) {
                ord++;
                UUID att = UUID.randomUUID(), sit = UUID.randomUUID();
                jdbc.sql("INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at) VALUES (:id, :s, 'OLEVEL', :n, :k, 'EXACT', :c, now())")
                        .param("id", att).param("s", SESSION).param("n", jamb + "-olevel-" + ord + ".json").param("k", jamb).param("c", cand).update();
                jdbc.sql("INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_year, exam_number, ord) VALUES (:id, :a, :s, :k, 'WAEC', :y, :no, 1)")
                        .param("id", sit).param("a", att).param("s", SESSION).param("k", jamb).param("y", String.valueOf(2084 + ord)).param("no", "WAEC/" + n + "/" + ord).update();
                for (Map<String, String> g : sitting) {
                    jdbc.sql("INSERT INTO admissions.olevel_grade (sitting_id, subject, grade) VALUES (:s, :j, :g)").param("s", sit).param("j", g.get("s")).param("g", g.get("g")).update();
                }
            }
            return new Applicant(appId, acct, cand, jamb, surname);
        });
    }

    static Map<String, String> g(String subject, String grade) {
        return Map.of("s", subject, "g", grade);
    }

    static final List<Map<String, String>> SCIENCE = List.of(g("English Language", "C6"), g("Mathematics", "B3"), g("Physics", "C5"), g("Chemistry", "C6"), g("Biology", "C4"), g("Economics", "B3"));
    static final List<Map<String, String>> COMMERCIAL = List.of(g("English Language", "B3"), g("Mathematics", "C6"), g("Economics", "B2"), g("Accounting", "C5"), g("Commerce", "C6"), g("Government", "B3"));
    static final List<String> UTME_SCIENCE = List.of("English Language", "Mathematics", "Physics", "Chemistry");
    static final List<String> UTME_COMMERCIAL = List.of("English Language", "Mathematics", "Economics", "Government");

    @SuppressWarnings("unchecked")
    Map<String, Object> detail(String token, UUID app) {
        ResponseEntity<Map> r = it.get(token, PATH + "/eligibility/" + app);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        return r.getBody();
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> run(Map<String, Object> d) {
        return (Map<String, Object>) d.get("run");
    }

    @SuppressWarnings("unchecked")
    static List<Map<String, Object>> alternatives(Map<String, Object> d) {
        return (List<Map<String, Object>>) d.get("alternatives");
    }

    @SuppressWarnings("unchecked")
    static List<String> reasons(Map<String, Object> row) {
        return (List<String>) row.get("reasons");
    }

    static String applicantToken(Applicant a) {
        return TestTokens.token(a.account(), List.of("applicant"));
    }

    /* ── 1–4 · eligible, not eligible with alternatives, explained, and none ── */
    @Test
    @Order(1)
    @SuppressWarnings("unchecked")
    void theVerdictsAreReadFromTheSettingsAndExplained() {
        Applicant eligible = applicant(CS, 210, UTME_SCIENCE, SCIENCE);
        Applicant notEligible = applicant(CS, 210, UTME_COMMERCIAL, COMMERCIAL);
        Applicant hopeless = applicant(CS, 120, UTME_COMMERCIAL, COMMERCIAL);

        // submitted, not yet evaluated: the Office evaluates the unevaluated in one act
        ResponseEntity<Map> all = it.call(academic, HttpMethod.POST, PATH + "/eligibility/recalculate-all?onlyMissing=true", Map.of());
        assertThat(all.getStatusCode().value()).as(String.valueOf(all.getBody())).isEqualTo(200);
        assertThat(((Number) all.getBody().get("evaluated")).intValue()).isGreaterThanOrEqualTo(3);

        // 1 · every rule met → ELIGIBLE, and no alternative is searched
        Map<String, Object> d1 = detail(academic, eligible.app());
        assertThat(run(d1).get("applied_result")).isEqualTo("ELIGIBLE");
        assertThat(run(d1).get("applied_programme_code")).isEqualTo(CS);
        assertThat(run(d1).get("policy_state")).isEqualTo("IN_FORCE");
        assertThat(alternatives(d1)).isEmpty();
        Map<String, Object> applied1 = (Map<String, Object>) d1.get("applied");
        assertThat(reasons(applied1)).isEmpty();
        assertThat(String.valueOf(applied1.get("checks"))).contains("\"kind\": \"OLEVEL_REQUIRED\"").contains("\"kind\": \"UTME_SCORE\"").contains("\"kind\": \"UTME_COMBINATION\"");

        // 2 · a required O'Level subject missing → NOT ELIGIBLE, the requirement named, the alternatives listed with the eligible first
        Map<String, Object> d2 = detail(academic, notEligible.app());
        assertThat(run(d2).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        Map<String, Object> applied2 = (Map<String, Object>) d2.get("applied");
        assertThat(reasons(applied2)).anyMatch(x -> x.contains("Physics")).anyMatch(x -> x.contains("UTME subject"));
        List<Map<String, Object>> alts = alternatives(d2);
        assertThat(alts).isNotEmpty();
        List<String> eligibleCodes = alts.stream().filter(a -> "ELIGIBLE".equals(a.get("result"))).map(a -> String.valueOf(a.get("programme_code"))).toList();
        assertThat(eligibleCodes).containsExactlyInAnyOrder(ACC, ECO);
        assertThat(((Number) run(d2).get("alternatives")).intValue()).isEqualTo(2);
        // the eligible come first; a closed programme and one without a rule are never among the suggestions
        assertThat(alts.get(0).get("result")).isEqualTo("ELIGIBLE");
        assertThat(alts.stream().map(a -> a.get("programme_code"))).doesNotContain(MBBS).doesNotContain("C00002");

        // 3 · explained check by check: requirement · candidate · result
        String checks = String.valueOf(applied2.get("checks"));
        assertThat(checks).contains("\"status\": \"NOT_MET\"").contains("\"label\": \"Physics\"").contains("\"requirement\"").contains("\"candidate\"");

        // 4 · a score under every minimum qualifies for nothing, and the verdict says so
        Map<String, Object> d3 = detail(academic, hopeless.app());
        assertThat(run(d3).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        assertThat(((Number) run(d3).get("alternatives")).intValue()).isZero();
        assertThat(alternatives(d3).stream().filter(a -> "ELIGIBLE".equals(a.get("result")))).isEmpty();
        assertThat(reasons((Map<String, Object>) d3.get("applied"))).anyMatch(x -> x.contains("120") && x.contains("below the minimum"));

        // 10 · the trail: evaluated, recommendation generated, viewed by the office
        List<Map<String, Object>> events = (List<Map<String, Object>>) d2.get("events");
        assertThat(events.stream().map(e -> e.get("action"))).contains("EVALUATED", "RECOMMENDATION_GENERATED");
        long viewed = jdbc.sql("SELECT count(*) FROM admissions.eligibility_event WHERE application_id = :a AND action = 'RECOMMENDATION_VIEWED'").param("a", notEligible.app()).query(Long.class).single();
        assertThat(viewed).isGreaterThanOrEqualTo(1);
        // the applicant was told, without a promise of admission
        long told = jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND subject LIKE '%programme eligibility%'").param("a", notEligible.app()).query(Long.class).single();
        assertThat(told).isGreaterThanOrEqualTo(1);
    }

    /* ── 5 · sittings: combined when the rule allows two, refused when it allows one; the rule change re-evaluates by itself ── */
    @Test
    @Order(2)
    void twoSittingsAreCombinedOnlyWhenTheRuleAllowsIt() {
        Applicant two = applicant(CS, 205, UTME_SCIENCE,
                List.of(g("English Language", "C6"), g("Mathematics", "C6"), g("Physics", "F9"), g("Chemistry", "C6"), g("Biology", "D7")),
                List.of(g("Physics", "C5"), g("Biology", "C6"), g("Economics", "C6"), g("Geography", "B3")));
        Map<String, Object> d = detail(academic, two.app());
        assertThat(run(d).get("applied_result")).as(String.valueOf(d.get("applied"))).isEqualTo("ELIGIBLE");
        int version = ((Number) run(d).get("rules_version")).intValue();

        // Senate allows one sitting only for Computer Science: the rules version moves
        it.db(() -> jdbc.sql("UPDATE admissions.programme_rule SET olevel_sittings = 1 WHERE policy_id = :p AND programme_code = :c").param("p", POLICY).param("c", CS).update());
        Map<String, Object> after = detail(academic, two.app());
        assertThat(((Number) run(after).get("rules_version")).intValue()).isGreaterThan(version);
        assertThat(run(after).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        assertThat(String.valueOf(after.get("applied"))).contains("One sitting only");
        assertThat(run(after).get("trigger_kind")).isEqualTo("POLICY_CHANGE");
        // and back
        it.db(() -> jdbc.sql("UPDATE admissions.programme_rule SET olevel_sittings = 2 WHERE policy_id = :p AND programme_code = :c").param("p", POLICY).param("c", CS).update());
        assertThat(run(detail(academic, two.app())).get("applied_result")).isEqualTo("ELIGIBLE");
    }

    /* ── 6 · an equivalence is honoured only when the Secretariat states it ── */
    @Test
    @Order(3)
    @SuppressWarnings("unchecked")
    void anEquivalenceIsHonouredOnlyWhenStated() {
        Applicant agric = applicant(CS, 215, List.of("English Language", "Mathematics", "Physics", "Agricultural Science"), SCIENCE);
        Map<String, Object> before = detail(academic, agric.app());
        assertThat(run(before).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        assertThat(reasons((Map<String, Object>) before.get("applied"))).anyMatch(x -> x.contains("Chemistry/Biology"));

        ResponseEntity<Map> saved = it.call(registrar, HttpMethod.PUT, PATH + "/policy/equivalences",
                Map.of("rows", List.of(Map.of("subject", "Biology", "equivalent", "Agricultural Science", "scope", "ANY"))));
        assertThat(saved.getStatusCode().value()).as(String.valueOf(saved.getBody())).isEqualTo(200);
        assertThat((List<Map<String, Object>>) saved.getBody().get("equivalences")).hasSize(1);

        Map<String, Object> after = detail(academic, agric.app());
        assertThat(run(after).get("applied_result")).as(String.valueOf(after.get("applied"))).isEqualTo("ELIGIBLE");
        assertThat(((Number) run(after).get("rules_version")).intValue()).isGreaterThan(((Number) run(before).get("rules_version")).intValue());

        // additional screening stated for the programme → academically eligible, screening required
        ResponseEntity<Map> scr = it.call(academic, HttpMethod.PUT, PATH + "/policy/programmes/" + CS + "/screening", Map.of("additionalScreening", "Aptitude test"));
        assertThat(scr.getStatusCode().value()).as(String.valueOf(scr.getBody())).isEqualTo(200);
        assertThat(run(detail(academic, agric.app())).get("applied_result")).isEqualTo("ELIGIBLE_SCREENING");
        it.call(academic, HttpMethod.PUT, PATH + "/policy/programmes/" + CS + "/screening", Map.of("additionalScreening", ""));
        assertThat(run(detail(academic, agric.app())).get("applied_result")).isEqualTo("ELIGIBLE");
    }

    /* ── 7 · the officers' register: search, filters, statistics ── */
    @Test
    @Order(4)
    @SuppressWarnings("unchecked")
    void theRegisterIsSearchedAndFilteredOnTheServer() {
        Applicant b = applicant(CS, 190, UTME_COMMERCIAL, COMMERCIAL);
        detail(academic, b.app());

        Map<String, Object> notEligible = it.get(academic, PATH + "/eligibility?status=NOT_ELIGIBLE&q=" + b.surname()).getBody();
        List<Map<String, Object>> rows = (List<Map<String, Object>>) notEligible.get("rows");
        assertThat(rows).hasSize(1);
        assertThat(rows.get(0).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        assertThat(String.valueOf(rows.get(0).get("top_alternatives"))).contains("ACCOUNTING").contains("ECONOMICS");
        assertThat((List<String>) rows.get(0).get("reasons")).isNotEmpty();

        // the recommended-programme filter: found under Accounting, not under MBBS
        assertThat((List<?>) it.get(academic, PATH + "/eligibility?recommended=" + ACC + "&q=" + b.surname()).getBody().get("rows")).hasSize(1);
        assertThat((List<?>) it.get(academic, PATH + "/eligibility?recommended=" + MBBS + "&q=" + b.surname()).getBody().get("rows")).isEmpty();
        assertThat((List<?>) it.get(academic, PATH + "/eligibility?status=ELIGIBLE&q=" + b.surname()).getBody().get("rows")).isEmpty();
        assertThat((List<?>) it.get(academic, PATH + "/eligibility?fac=SC&status=ALTERNATIVES&q=" + b.surname()).getBody().get("rows")).hasSize(1);
        assertThat((List<?>) it.get(academic, PATH + "/eligibility?fac=MS&q=" + b.surname()).getBody().get("rows")).isEmpty();

        Map<String, Object> stats = (Map<String, Object>) notEligible.get("stats");
        assertThat(((Number) stats.get("evaluated")).intValue()).isGreaterThanOrEqualTo(4);
        assertThat(((Number) stats.get("with_alternatives")).intValue()).isGreaterThanOrEqualTo(2);
        assertThat(((Number) stats.get("without_alternatives")).intValue()).isGreaterThanOrEqualTo(1);
        assertThat(((Number) stats.get("eligible")).intValue()).isGreaterThanOrEqualTo(1);
        List<Map<String, Object>> recommendable = (List<Map<String, Object>>) notEligible.get("recommendable");
        assertThat(recommendable.stream().map(r -> r.get("programme_code"))).contains(ACC, ECO);
    }

    /* ── 8 · the applicant: their own verdict, a request for a suggested programme only, the Office's decision ── */
    @Test
    @Order(5)
    @SuppressWarnings("unchecked")
    void theApplicantMayAskOnlyForASuggestedProgrammeAndTheOfficeDecides() {
        Applicant b = applicant(CS, 195, UTME_COMMERCIAL, COMMERCIAL);
        String me = applicantToken(b);

        ResponseEntity<Map> mine = it.get(me, "/api/v1/applicant/me/eligibility");
        assertThat(mine.getStatusCode().value()).as(String.valueOf(mine.getBody())).isEqualTo(200);
        assertThat(mine.getBody().get("available")).isEqualTo(true);
        assertThat(run((Map<String, Object>) mine.getBody()).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        assertThat(mine.getBody().get("canRequestChange")).isEqualTo(true);
        assertThat(((Map<String, Object>) mine.getBody().get("application")).get("application_no")).isEqualTo(
                jdbc.sql("SELECT application_no FROM admissions.application WHERE id = :a").param("a", b.app()).query(String.class).single());
        // the applicant sees the programmes they qualify for, never the ones they do not
        assertThat(alternatives((Map<String, Object>) mine.getBody())).isNotEmpty().allMatch(a -> List.of("ELIGIBLE", "ELIGIBLE_SCREENING").contains(String.valueOf(a.get("result"))));

        // a programme not among the suggestions is refused
        ResponseEntity<Map> refused = it.call(me, HttpMethod.POST, "/api/v1/applicant/me/eligibility/change", Map.of("programmeCode", MBBS, "note", "please"));
        assertThat(refused.getStatusCode().value()).isEqualTo(422);
        assertThat(String.valueOf(refused.getBody())).contains("ELIG_NOT_SUGGESTED");

        // a suggested one is requested — and nothing changes yet
        ResponseEntity<Map> asked = it.call(me, HttpMethod.POST, "/api/v1/applicant/me/eligibility/change", Map.of("programmeCode", ECO, "note", "I would like Economics"));
        assertThat(asked.getStatusCode().value()).as(String.valueOf(asked.getBody())).isEqualTo(200);
        assertThat(asked.getBody().get("canRequestChange")).isEqualTo(false);
        List<Map<String, Object>> changes = (List<Map<String, Object>>) asked.getBody().get("changes");
        assertThat(changes).hasSize(1);
        assertThat(changes.get(0).get("state")).isEqualTo("REQUESTED");
        String reqId = String.valueOf(changes.get(0).get("id"));
        assertThat(jdbc.sql("SELECT programme FROM admissions.candidate WHERE id = :c").param("c", b.candidate()).query(String.class).single()).isEqualTo("B.Sc. COMPUTER SCIENCE");
        // a second open request is refused
        assertThat(it.call(me, HttpMethod.POST, "/api/v1/applicant/me/eligibility/change", Map.of("programmeCode", ACC)).getStatusCode().value()).isIn(409, 422);

        // the Office sees it on the queue and a rejection needs a reason
        List<Map<String, Object>> queue = it.getList(academic, PATH + "/eligibility/changes?state=REQUESTED").getBody();
        assertThat(queue.stream().map(c -> c.get("id"))).contains(reqId);
        assertThat(it.call(academic, HttpMethod.POST, PATH + "/eligibility/changes/" + reqId + "/reject", Map.of("note", "")).getStatusCode().value()).isEqualTo(422);

        // approved: the programme changes on the record, the evaluation is re-run under PROGRAMME_CHANGE, the applicant is told
        ResponseEntity<Map> ok = it.call(academic, HttpMethod.POST, PATH + "/eligibility/changes/" + reqId + "/approve", Map.of("note", "Within quota"));
        assertThat(ok.getStatusCode().value()).as(String.valueOf(ok.getBody())).isEqualTo(200);
        assertThat(jdbc.sql("SELECT programme FROM admissions.candidate WHERE id = :c").param("c", b.candidate()).query(String.class).single()).isEqualTo("B.Sc. ECONOMICS");
        Map<String, Object> after = detail(academic, b.app());
        assertThat(run(after).get("applied_result")).isEqualTo("ELIGIBLE");
        assertThat(run(after).get("applied_programme_code")).isEqualTo(ECO);
        assertThat(run(after).get("trigger_kind")).isEqualTo("PROGRAMME_CHANGE");
        assertThat(((List<Map<String, Object>>) after.get("changes")).get(0).get("state")).isEqualTo("APPROVED");
        assertThat(((List<Map<String, Object>>) after.get("events")).stream().map(e -> e.get("action"))).contains("PROGRAMME_CHANGE_REQUESTED", "PROGRAMME_CHANGE_APPROVED");
        assertThat(jdbc.sql("SELECT count(*) FROM platform.notice WHERE about_kind = 'application' AND about_id = :a AND subject LIKE '%programme%'").param("a", b.app()).query(Long.class).single()).isGreaterThanOrEqualTo(2);
        // the applicant's own view agrees, and no admission was granted by it
        assertThat(run((Map<String, Object>) it.get(me, "/api/v1/applicant/me/eligibility").getBody()).get("applied_result")).isEqualTo("ELIGIBLE");
        assertThat(jdbc.sql("SELECT offer_state FROM admissions.candidate WHERE id = :c").param("c", b.candidate()).query(String.class).single()).isEqualTo("PROPOSED");
        assertThat(jdbc.sql("SELECT decision FROM admissions.application WHERE id = :a").param("a", b.app()).query().singleRow().get("decision")).isNull();
    }

    /* ── 9 · a change to the record marks the reading stale; it is re-read on the next open ── */
    @Test
    @Order(6)
    void aChangedRecordIsReReadOnTheNextOpen() {
        Applicant a = applicant(CS, 150, UTME_SCIENCE, SCIENCE);
        Map<String, Object> low = detail(academic, a.app());
        assertThat(run(low).get("applied_result")).isEqualTo("NOT_ELIGIBLE");
        String firstRun = String.valueOf(run(low).get("id"));

        it.db(() -> jdbc.sql("UPDATE admissions.caps_row SET aggregate = 230 WHERE session = :s AND jamb_key = :k").param("s", SESSION).param("k", a.jamb()).update());
        assertThat(jdbc.sql("SELECT stale FROM admissions.eligibility_run WHERE id = :r").param("r", UUID.fromString(firstRun)).query(Boolean.class).single()).isTrue();
        Map<String, Object> again = detail(academic, a.app());
        assertThat(run(again).get("id")).isNotEqualTo(firstRun);
        assertThat(run(again).get("applied_result")).isEqualTo("ELIGIBLE");
        assertThat(run(again).get("stale")).isEqualTo(false);

        // and the officer's own recalculation is a new run under OFFICER
        ResponseEntity<Map> re = it.call(academic, HttpMethod.POST, PATH + "/eligibility/" + a.app() + "/recalculate", Map.of());
        assertThat(re.getStatusCode().value()).isEqualTo(200);
        assertThat(run((Map<String, Object>) re.getBody()).get("trigger_kind")).isEqualTo("OFFICER");
        assertThat(jdbc.sql("SELECT count(*) FROM admissions.eligibility_run WHERE application_id = :a AND superseded_at IS NULL").param("a", a.app()).query(Long.class).single()).isEqualTo(1);
    }

    /* ── 10 · the doors ── */
    @Test
    @Order(7)
    void theDoorsAreKept() {
        Applicant a = applicant(CS, 210, UTME_SCIENCE, SCIENCE);
        Applicant other = applicant(CS, 210, UTME_SCIENCE, SCIENCE);
        // an office without the door
        assertThat(it.get(housing, PATH + "/eligibility").getStatusCode().value()).isEqualTo(403);
        assertThat(it.get(housing, PATH + "/eligibility/" + a.app()).getStatusCode().value()).isEqualTo(403);
        // an applicant at the officers' doors
        assertThat(it.get(applicantToken(a), PATH + "/eligibility").getStatusCode().value()).isEqualTo(403);
        assertThat(it.call(applicantToken(a), HttpMethod.POST, PATH + "/eligibility/recalculate-all", Map.of()).getStatusCode().value()).isEqualTo(403);
        // a reader that may not act
        assertThat(it.get(ItSupport.token("bursar"), PATH + "/eligibility").getStatusCode().value()).isEqualTo(200);
        assertThat(it.call(ItSupport.token("bursar"), HttpMethod.POST, PATH + "/eligibility/" + a.app() + "/recalculate", Map.of()).getStatusCode().value()).isEqualTo(403);
        // each applicant reads only their own application
        assertThat(((Map<?, ?>) it.get(applicantToken(other), "/api/v1/applicant/me/eligibility").getBody().get("application")).get("id")).isEqualTo(other.app().toString());
        assertThat(it.get(applicantToken(other), "/api/v1/applicant/me/eligibility").getBody().toString()).doesNotContain(a.app().toString());
        // nobody at all
        assertThat(it.anon(HttpMethod.GET, PATH + "/eligibility", null).getStatusCode().value()).isEqualTo(401);
    }
}
