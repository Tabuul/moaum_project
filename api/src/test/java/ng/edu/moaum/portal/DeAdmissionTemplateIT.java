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
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.PlatformTransactionManager;

/**
 * V764: the Direct Entry admission template through the API (GET …/de-template), in a session of its own with its own admission
 * settings in force: programme C00019 (B.Sc. Accounting) with a quota of 10, the session's UTME:DE ratio 80:20 (so a Direct Entry
 * share of 2) and a Direct Entry requirement of two of Chemistry, Biology and Physics. Three made-up Direct Entry applicants — D1
 * A-Level A B C offered by the Board on National Merit, D2 JUPEB A A B and no decision yet, D3 with no qualification captured —
 * a fourth on JAMB's Direct Entry list who never registered, and a UTME applicant of the same programme. The rows are the three
 * registered Direct Entry applicants, ranked by points (D2 14, D1 12, D3 last), each placed and explained; the summary counts JAMB's
 * Direct Entry list, the registered, the qualified and not, the quota and its Direct Entry share, the merit list; the quota
 * distribution is over the Direct Entry share; an office that does not read admissions is refused.
 */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT,
        properties = "moaum.auth.hmac-secret=" + TestTokens.SECRET)
@EnabledIfEnvironmentVariable(named = "DATABASE_URL", matches = ".+")
class DeAdmissionTemplateIT {

    static final String PROG = "C00019";

    @Value("${local.server.port}")
    int port;
    @Autowired
    JdbcClient jdbc;
    @Autowired
    PlatformTransactionManager transactions;

    ItSupport it;
    final String academic = ItSupport.token("academic");

    @BeforeEach
    void setUp() {
        it = new ItSupport(port, jdbc, transactions);
    }

    @Test
    @SuppressWarnings("unchecked")
    void everyRegisteredDirectEntryApplicantIsARankedRowQualifiedOrNotWithTheReasons() {
        int y = it.freeYear(7600, 7700);
        String ses = y + "/" + (y + 1);
        String yy = String.format("%02d", (y + 1) % 100);
        String name = it.db(() -> jdbc.sql("SELECT name FROM ref.programme WHERE code = :c").param("c", PROG).query(String.class).single());
        UUID pol = UUID.randomUUID(), grp = UUID.randomUUID(), batch = UUID.randomUUID(), ubatch = UUID.randomUUID(), who = UUID.randomUUID();
        it.db(() -> {
            jdbc.sql("INSERT INTO iam.person (id, surname, given_names) VALUES (:w, 'ZZDEIT', 'Recorder')").param("w", who).update();
            jdbc.sql("INSERT INTO policy.academic_session (id, name, starts_on, ends_on) VALUES (gen_random_uuid(), :s, make_date(:y, 10, 1), make_date(:y + 1, 8, 31)) ON CONFLICT (name) DO NOTHING")
                    .param("s", ses).param("y", y).update();
            jdbc.sql("""
                    INSERT INTO admissions.session_policy (id, session, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, instrument, in_force, state)
                    VALUES (:p, :s, 10, 70, 30, 80, 20, 'IT CAC/DE/1', tstzrange(now(), NULL), 'IN_FORCE')
                    """).param("p", pol).param("s", ses).update();
            jdbc.sql("""
                    INSERT INTO admissions.selection_criterion (policy_id, criterion, percent)
                    VALUES (:p, 'NATIONAL_MERIT', 50), (:p, 'STATE_MERIT', 30), (:p, 'ELG', 10), (:p, 'LOCALITY', 10)
                    """).param("p", pol).update();
            jdbc.sql("INSERT INTO admissions.programme_rule (policy_id, programme_code, quota, olevel_text, utme_text, de_text) VALUES (:p, :c, 10, 'it', 'it', 'it')")
                    .param("p", pol).param("c", PROG).update();
            jdbc.sql("INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose) VALUES (:g, :p, :c, 'DE', 2)")
                    .param("g", grp).param("p", pol).param("c", PROG).update();
            jdbc.sql("INSERT INTO admissions.rule_subject (group_id, subject) VALUES (:g, 'Chemistry'), (:g, 'Biology'), (:g, 'Physics')").param("g", grp).update();
            jdbc.sql("""
                    INSERT INTO admissions.caps_batch (id, session, source, list_kind, file_sha256, rows_read, downloaded_on, uploaded_by, uploaded_office)
                    VALUES (:b, :s, 'CAPS_DOWNLOAD', 'DIRECT_ENTRY', decode(md5(:s || 'de'), 'hex'), 4, current_date, :w, 'academic'),
                           (:u, :s, 'CAPS_DOWNLOAD', 'UTME', decode(md5(:s || 'utme'), 'hex'), 1, current_date, :w, 'academic')
                    """).param("b", batch).param("u", ubatch).param("s", ses).param("w", who).update();
            return null;
        });
        String[][] people = {
            // tag, mode, registered, basis, subjects "subject:grade,…"
            {"D1", "DIRECT_ENTRY", "yes", "A_LEVEL", "Chemistry:A,Biology:B,Physics:C"},
            {"D2", "DIRECT_ENTRY", "yes", "JUPEB", "Chemistry:A,Biology:A,Physics:B"},
            {"D3", "DIRECT_ENTRY", "yes", null, null},
            {"D4", "DIRECT_ENTRY", "no", null, null},
            {"U1", "UTME", "yes", null, null},
        };
        java.util.Map<String, UUID> apps = new java.util.HashMap<>();
        for (int i = 0; i < people.length; i++) {
            String[] p = people[i];
            String jamb = y + "640000" + (i + 1);
            int n = i;
            UUID app = it.db(() -> {
                UUID cr = UUID.randomUUID(), cand = UUID.randomUUID(), acct = UUID.randomUUID(), a = UUID.randomUUID();
                boolean utme = "UTME".equals(p[1]);
                jdbc.sql("""
                        INSERT INTO admissions.caps_row (id, batch_id, session, jamb_reg_no, raw, surname, other_names, jamb_code, aggregate, entry_mode, sex, state_of_origin, lga)
                        VALUES (:id, :b, :s, :j, '{}'::jsonb, 'ZZDEIT', :t, :c, :agg, :m, 'F', 'Benue', 'Makurdi')
                        """).param("id", cr).param("b", utme ? ubatch : batch).param("s", ses).param("j", jamb).param("t", p[0]).param("c", PROG)
                        .param("agg", utme ? 250 : null, java.sql.Types.INTEGER).param("m", p[1]).update();
                if (!"yes".equals(p[2])) {
                    return null;
                }
                jdbc.sql("""
                        INSERT INTO admissions.candidate (id, session, jamb_reg_no, surname, other_names, programme, entry_mode, entry_level, offer_state, admitted_from)
                        VALUES (:id, :s, :j, 'ZZDEIT', :t, :name, :m, :lvl, 'PROPOSED', :cr)
                        """).param("id", cand).param("s", ses).param("j", jamb).param("t", p[0]).param("name", name).param("m", p[1])
                        .param("lvl", utme ? 100 : 200).param("cr", cr).update();
                jdbc.sql("""
                        INSERT INTO admissions.applicant_account (id, session, candidate_id, jamb_key, email, phone, password_hash)
                        VALUES (:id, :s, :c, :j, lower(:j) || '@example.com', '08030007640', crypt('x', gen_salt('bf', 12)))
                        """).param("id", acct).param("s", ses).param("c", cand).param("j", jamb).update();
                jdbc.sql("""
                        INSERT INTO admissions.application (id, account_id, candidate_id, session, application_no, fee_confirmed_at, submitted_at)
                        VALUES (:id, :acct, :c, :s, :no, now(), now())
                        """).param("id", a).param("acct", acct).param("c", cand).param("s", ses)
                        .param("no", "APP/" + yy + "/76" + String.format("%04d", (y % 100) * 10 + n)).update();
                UUID att = UUID.randomUUID(), sit = UUID.randomUUID();
                jdbc.sql("""
                        INSERT INTO admissions.attachment (id, session, kind, source_name, jamb_key, read_as, candidate_id, matched_at)
                        VALUES (:id, :s, 'OLEVEL', :j || '-olevel.json', :j, 'EXACT', :c, now())
                        """).param("id", att).param("s", ses).param("j", jamb).param("c", cand).update();
                jdbc.sql("""
                        INSERT INTO admissions.olevel_sitting (id, attachment_id, session, jamb_key, exam_body, exam_year, exam_number, ord)
                        VALUES (:id, :att, :s, :j, 'WAEC', '2020', 'WAEC/' || :j, 1)
                        """).param("id", sit).param("att", att).param("s", ses).param("j", jamb).update();
                jdbc.sql("""
                        INSERT INTO admissions.olevel_grade (sitting_id, subject, grade)
                        VALUES (:sit, 'English Language', 'B3'), (:sit, 'Mathematics', 'C4'), (:sit, 'Physics', 'C5'), (:sit, 'Chemistry', 'C6'), (:sit, 'Biology', 'C4')
                        """).param("sit", sit).update();
                if (p[3] != null) {
                    UUID aw = UUID.randomUUID();
                    jdbc.sql("""
                            INSERT INTO admissions.de_award (id, session, jamb_key, basis, awarded_year, institution, recorded_by)
                            VALUES (:id, :s, :j, :basis, 2024, 'IT College', :w)
                            """).param("id", aw).param("s", ses).param("j", jamb).param("basis", p[3]).param("w", who).update();
                    for (String sg : p[4].split(",")) {
                        String[] x = sg.split(":");
                        jdbc.sql("INSERT INTO admissions.de_award_subject (award_id, subject, grade) VALUES (:a, :sub, :g)")
                                .param("a", aw).param("sub", x[0]).param("g", x[1]).update();
                    }
                }
                return a;
            });
            if (app != null) {
                apps.put(p[0], app);
            }
        }
        // the Board offered D1 on National Merit
        it.db(() -> jdbc.sql("UPDATE admissions.application SET decision = 'OFFERED', decision_basis = 'NM' WHERE id = :a").param("a", apps.get("D1")).update());

        String path = "/api/v1/admissions/sessions/" + y + "/" + (y + 1) + "/de-template?programme=" + name;
        ResponseEntity<Map> r = it.get(academic, path);
        assertThat(r.getStatusCode().value()).as(String.valueOf(r.getBody())).isEqualTo(200);
        Map<String, Object> summary = (Map<String, Object>) r.getBody().get("summary");
        assertThat(summary).containsEntry("totalApplicants", 4).containsEntry("registeredApplicants", 3).containsEntry("qualifiedCases", 2)
                .containsEntry("nonQualifiedCases", 1).containsEntry("totalQuota", 10).containsEntry("deQuota", 2).containsEntry("deRatio", 20)
                .containsEntry("numberOnMeritList", 1);
        List<Map<String, Object>> rows = (List<Map<String, Object>>) r.getBody().get("rows");
        assertThat(rows).extracting(x -> x.get("name")).containsExactly("ZZDEIT D2", "ZZDEIT D1", "ZZDEIT D3");
        assertThat(rows).extracting(x -> x.get("rank")).containsExactly(1, 2, 3);
        assertThat(rows.get(0)).containsEntry("qualification", "JUPEB").containsEntry("points", 14).containsEntry("decision", "WAITING")
                .containsEntry("qualified", true).containsEntry("deStatus", "MET").containsEntry("decisionNote", "Qualified: no decision recorded yet")
                .containsEntry("engGrade", "B3").containsEntry("mathsGrade", "C4");
        assertThat((List<Map<String, Object>>) rows.get(0).get("subjects")).first()
                .satisfies(s -> assertThat(s).containsEntry("subject", "Biology").containsEntry("grade", "A").containsEntry("points", 5));
        assertThat(rows.get(1)).containsEntry("qualification", "A_LEVEL").containsEntry("points", 12).containsEntry("decision", "OFFERED")
                .containsEntry("decisionBasis", "NM").containsEntry("recordedDecision", "OFFERED");
        assertThat(rows.get(2)).containsEntry("decision", "NOT_OFFERED").containsEntry("qualified", false)
                .containsEntry("reason", "Direct Entry qualification not captured").containsEntry("deStatus", "UNVERIFIED");
        List<Map<String, Object>> quota = (List<Map<String, Object>>) r.getBody().get("quotaDistribution");
        assertThat(quota).anySatisfy(q -> assertThat(q).containsEntry("criterion", "National Merit").containsEntry("percent", 50)
                .containsEntry("quota", 1).containsEntry("admitted", 1));
        assertThat((Map<String, Object>) r.getBody().get("lgaTotal")).containsEntry("nm", 1).containsEntry("total", 1);

        // every programme of the session: the same rows (the UTME applicant never one of them)
        ResponseEntity<Map> all = it.get(academic, "/api/v1/admissions/sessions/" + y + "/" + (y + 1) + "/de-template");
        assertThat(all.getStatusCode().value()).isEqualTo(200);
        assertThat((List<Map<String, Object>>) all.getBody().get("rows")).extracting(x -> x.get("name")).containsExactly("ZZDEIT D2", "ZZDEIT D1", "ZZDEIT D3");

        // an office that does not read admissions is refused
        assertThat(it.get(ItSupport.token("lecturer"), path).getStatusCode().value()).isEqualTo(403);
    }
}
