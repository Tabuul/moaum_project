package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The settings tables of V008, read and written one session at a time. */
@Repository
class AdmissionSettingsRepository {

    private final JdbcClient jdbc;

    AdmissionSettingsRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<AdmissionPolicy.Summary> policies() {
        return jdbc.sql("SELECT session, state FROM admissions.session_policy ORDER BY session DESC")
                .query(AdmissionPolicy.Summary.class)
                .list();
    }

    Optional<AdmissionPolicy.Row> row(String session) {
        return jdbc.sql("""
                SELECT session, state, instrument, lower(in_force) AS in_force_since, nuc_quota, weight_utme, weight_putme,
                       ratio_utme, ratio_de, ratio_science, ratio_arts, elg_cap_pct, dept_share_pct,
                       index_prelim_places, index_per_zone, mpf_only, screening_required
                  FROM admissions.session_policy WHERE session = :session
                """)
                .param("session", session)
                .query(AdmissionPolicy.Row.class)
                .optional();
    }

    Optional<UUID> id(String session) {
        return jdbc.sql("SELECT id FROM admissions.session_policy WHERE session = :session")
                .param("session", session)
                .query(UUID.class)
                .optional();
    }

    List<AdmissionPolicy.Criterion> criteria(String session) {
        return jdbc.sql("""
                SELECT c.criterion, c.percent
                  FROM admissions.selection_criterion c
                  JOIN admissions.session_policy p ON p.id = c.policy_id
                 WHERE p.session = :session
                 ORDER BY CASE c.criterion WHEN 'NATIONAL_MERIT' THEN 1 WHEN 'STATE_MERIT' THEN 2 WHEN 'ELG' THEN 3 ELSE 4 END
                """)
                .param("session", session)
                .query(AdmissionPolicy.Criterion.class)
                .list();
    }

    /** Every programme the University runs, with this session's rule where one is stated. */
    List<AdmissionPolicy.ProgrammeRule> programmeRules(String session) {
        return jdbc.sql("""
                SELECT g.code, g.name, g.faculty_code, f.name AS faculty_name, r.cutoff, r.quota, r.olevel_text, r.utme_text,
                       r.de_text, r.olevel_credits, r.olevel_sittings, (r.programme_code IS NOT NULL) AS stated,
                       (SELECT string_agg(DISTINCT rs.subject, E'\n' ORDER BY rs.subject)
                          FROM admissions.rule_subject rs
                          JOIN admissions.rule_subject_group sg ON sg.id = rs.group_id
                         WHERE sg.policy_id = r.policy_id AND sg.programme_code = r.programme_code AND sg.scope = 'OLEVEL') AS olevel_subjects,
                       (SELECT string_agg(a.subject, E'\n' ORDER BY a.subject)
                          FROM admissions.programme_olevel_allowance a
                         WHERE a.policy_id = r.policy_id AND a.programme_code = r.programme_code) AS olevel_allowances,
                       (cl.programme_code IS NOT NULL) AS closed, cl.reason AS closed_reason
                  FROM ref.programme g
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  LEFT JOIN (SELECT r.* FROM admissions.programme_rule r
                               JOIN admissions.session_policy p ON p.id = r.policy_id
                              WHERE p.session = :session) r ON r.programme_code = g.code
                  LEFT JOIN (SELECT c.* FROM admissions.programme_closed c
                               JOIN admissions.session_policy p ON p.id = c.policy_id
                              WHERE p.session = :session) cl ON cl.programme_code = g.code
                 ORDER BY f.name, g.name
                """)
                .param("session", session)
                .query((rs, i) -> new AdmissionPolicy.ProgrammeRule(rs.getString("code"), rs.getString("name"),
                        rs.getString("faculty_code"), rs.getString("faculty_name"), rs.getObject("cutoff", Integer.class),
                        rs.getObject("quota", Integer.class),
                        rs.getString("olevel_text"), rs.getString("utme_text"), rs.getString("de_text"),
                        rs.getObject("olevel_credits", Integer.class), rs.getObject("olevel_sittings", Integer.class),
                        rs.getBoolean("stated"), lines(rs.getString("olevel_subjects")),
                        lines(rs.getString("olevel_allowances")),
                        rs.getBoolean("closed"), rs.getString("closed_reason")))
                .list();
    }

    private static List<String> lines(String text) {
        if (text == null || text.isBlank()) {
            return List.of();
        }
        return java.util.Arrays.stream(text.split("\\R")).map(String::trim).filter(s -> !s.isEmpty()).toList();
    }

    /** Creates the session's draft, or changes it while it is still one. */
    void upsertPolicy(String session, AdmissionSettingsService.PolicySettings s) {
        jdbc.sql("""
                INSERT INTO admissions.session_policy
                       (id, session, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, ratio_science, ratio_arts,
                        elg_cap_pct, dept_share_pct, index_prelim_places, index_per_zone, mpf_only, screening_required, state)
                VALUES (gen_random_uuid(), :session, :quota, :wu, :wp, :ru, :rd, :rs, :ra,
                        :elg, :dept, :prelim, :zone, :mpf, :screening, 'DRAFT')
                ON CONFLICT (session) DO UPDATE SET
                        nuc_quota = EXCLUDED.nuc_quota, weight_utme = EXCLUDED.weight_utme, weight_putme = EXCLUDED.weight_putme,
                        ratio_utme = EXCLUDED.ratio_utme, ratio_de = EXCLUDED.ratio_de,
                        ratio_science = EXCLUDED.ratio_science, ratio_arts = EXCLUDED.ratio_arts,
                        elg_cap_pct = EXCLUDED.elg_cap_pct, dept_share_pct = EXCLUDED.dept_share_pct,
                        index_prelim_places = EXCLUDED.index_prelim_places, index_per_zone = EXCLUDED.index_per_zone,
                        mpf_only = EXCLUDED.mpf_only, screening_required = EXCLUDED.screening_required
                """)
                .param("session", session)
                .param("quota", s.nucQuota())
                .param("wu", s.weightUtme())
                .param("wp", s.weightPutme())
                .param("ru", s.ratioUtme())
                .param("rd", s.ratioDe())
                .param("rs", s.ratioScience())
                .param("ra", s.ratioArts())
                .param("elg", s.elgCapPct())
                .param("dept", s.deptSharePct())
                .param("prelim", s.indexPrelimPlaces())
                .param("zone", s.indexPerZone())
                .param("mpf", s.mpfOnly())
                .param("screening", s.screeningRequired())
                .update();
    }

    void upsertCriterion(UUID policyId, String criterion, int percent) {
        jdbc.sql("""
                INSERT INTO admissions.selection_criterion (policy_id, criterion, percent) VALUES (:id, :c, :p)
                ON CONFLICT (policy_id, criterion) DO UPDATE SET percent = EXCLUDED.percent
                """)
                .param("id", policyId).param("c", criterion).param("p", percent)
                .update();
    }

    void upsertFacultyQuota(UUID policyId, String facultyCode, Integer quota, Integer cutoff, Integer ratioUtme, Integer ratioDe) {
        jdbc.sql("""
                INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff, ratio_utme, ratio_de) VALUES (:id, :f, :q, :k, :ru, :rd)
                ON CONFLICT (policy_id, faculty_code) DO UPDATE SET quota = EXCLUDED.quota, cutoff = EXCLUDED.cutoff,
                        ratio_utme = EXCLUDED.ratio_utme, ratio_de = EXCLUDED.ratio_de
                """)
                .param("id", policyId).param("f", facultyCode)
                .param("q", quota, Types.INTEGER).param("k", cutoff, Types.INTEGER)
                .param("ru", ratioUtme, Types.INTEGER).param("rd", ratioDe, Types.INTEGER)
                .update();
    }

    /* ── capacity: the NUC, faculty and programme quotas are places, not qualification rules, and
       the NUC ceiling can rise mid-cycle — so these three are editable even when the policy is in force.
       Each touches only its quota column; the cut-offs, weights, ratios and subject rules stay frozen. */

    int setNucQuota(UUID policyId, int quota) {
        return jdbc.sql("UPDATE admissions.session_policy SET nuc_quota = :q WHERE id = :id")
                .param("q", quota).param("id", policyId).update();
    }

    int setFacultyQuota(UUID policyId, String facultyCode, Integer quota) {
        return jdbc.sql("""
                INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota) VALUES (:id, :f, :q)
                ON CONFLICT (policy_id, faculty_code) DO UPDATE SET quota = EXCLUDED.quota
                """).param("id", policyId).param("f", facultyCode).param("q", quota, Types.INTEGER).update();
    }

    int setProgrammeQuota(UUID policyId, String code, Integer quota) {
        return jdbc.sql("UPDATE admissions.programme_rule SET quota = :q WHERE policy_id = :id AND programme_code = :code")
                .param("q", quota, Types.INTEGER).param("id", policyId).param("code", code).update();
    }

    void upsertProgrammeRule(UUID policyId, String code, AdmissionSettingsService.ProgrammeRuleIn r) {
        jdbc.sql("""
                INSERT INTO admissions.programme_rule
                       (policy_id, programme_code, cutoff, quota, olevel_credits, olevel_sittings, olevel_text, utme_text, de_text)
                VALUES (:id, :code, :cutoff, :quota, :credits, :sittings, :olevel, :utme, :de)
                ON CONFLICT (policy_id, programme_code) DO UPDATE SET
                        cutoff = EXCLUDED.cutoff, quota = EXCLUDED.quota, olevel_credits = EXCLUDED.olevel_credits,
                        olevel_sittings = EXCLUDED.olevel_sittings, olevel_text = EXCLUDED.olevel_text,
                        utme_text = EXCLUDED.utme_text, de_text = EXCLUDED.de_text
                """)
                .param("id", policyId).param("code", code)
                .param("cutoff", r.cutoff(), Types.INTEGER)
                .param("quota", r.quota(), Types.INTEGER)
                .param("credits", r.olevelCredits() == null ? 5 : r.olevelCredits())
                .param("sittings", r.olevelSittings() == null ? 2 : r.olevelSittings())
                .param("olevel", r.olevelText().trim())
                .param("utme", r.utmeText().trim())
                .param("de", r.deText().trim())
                .update();
        if (r.olevelSubjects() != null) {
            /* the relevant O'Level subjects, structured (V008 groups, V020 counts them): one group, replaced whole */
            jdbc.sql("""
                    DELETE FROM admissions.rule_subject WHERE group_id IN (
                        SELECT id FROM admissions.rule_subject_group WHERE policy_id = :id AND programme_code = :code AND scope = 'OLEVEL')
                    """).param("id", policyId).param("code", code).update();
            jdbc.sql("DELETE FROM admissions.rule_subject_group WHERE policy_id = :id AND programme_code = :code AND scope = 'OLEVEL'")
                    .param("id", policyId).param("code", code).update();
            List<String> subjects = r.olevelSubjects().stream().map(String::trim).filter(s -> !s.isEmpty()).distinct().toList();
            if (!subjects.isEmpty()) {
                UUID group = UUID.randomUUID();
                jdbc.sql("""
                        INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose, min_grade)
                        VALUES (:g, :id, :code, 'OLEVEL', :choose, 'C6')
                        """).param("g", group).param("id", policyId).param("code", code)
                        .param("choose", Math.min(subjects.size(), r.olevelCredits() == null ? 5 : r.olevelCredits())).update();
                for (String subject : subjects) {
                    jdbc.sql("INSERT INTO admissions.rule_subject (group_id, subject) VALUES (:g, :s)").param("g", group).param("s", subject).update();
                }
            }
        }
        if (r.olevelAllowances() != null) {
            /* the compulsory subjects this programme accepts a pass in (V053): replaced whole */
            jdbc.sql("DELETE FROM admissions.programme_olevel_allowance WHERE policy_id = :id AND programme_code = :code")
                    .param("id", policyId).param("code", code).update();
            for (String subject : r.olevelAllowances().stream().map(String::trim).filter(s -> !s.isEmpty()).distinct().toList()) {
                jdbc.sql("INSERT INTO admissions.programme_olevel_allowance (policy_id, programme_code, subject) VALUES (:id, :code, :s)")
                        .param("id", policyId).param("code", code).param("s", subject).update();
            }
        }
    }

    /** the catchment local governments stated on the policy, for the Locality basis (V054) */
    List<String> catchmentLgas(String session) {
        return jdbc.sql("""
                SELECT cl.lga FROM admissions.catchment_lga cl
                  JOIN admissions.session_policy p ON p.id = cl.policy_id
                 WHERE p.session = :session ORDER BY cl.lga
                """).param("session", session).query(String.class).list();
    }

    /** replaces the catchment set for the policy */
    void saveCatchment(UUID policyId, List<String> lgas) {
        jdbc.sql("DELETE FROM admissions.catchment_lga WHERE policy_id = :id").param("id", policyId).update();
        for (String lga : lgas) {
            jdbc.sql("INSERT INTO admissions.catchment_lga (policy_id, lga) VALUES (:id, :l) ON CONFLICT DO NOTHING")
                    .param("id", policyId).param("l", lga).update();
        }
    }

    /** the general UTME cut-off the session loads its JAMB lists under (V024) */
    Optional<Integer> loadCutoff(String session) {
        return jdbc.sql("SELECT admissions.load_cutoff_for(:s)").param("s", session).query(Integer.class).optional();
    }

    void stateLoadCutoff(String session, int cutoff) {
        jdbc.sql("""
                INSERT INTO admissions.load_cutoff (session, cutoff, stated_at) VALUES (:s, :c, now())
                ON CONFLICT (session) DO UPDATE SET cutoff = EXCLUDED.cutoff, stated_at = now()
                """).param("s", session).param("c", cutoff).update();
    }

    /** closed for the session (V023): not admitted into, needs no rule; the reason goes on the record */
    void closeProgramme(UUID policyId, String code, String reason) {
        jdbc.sql("""
                INSERT INTO admissions.programme_closed (policy_id, programme_code, reason) VALUES (:id, :code, :reason)
                ON CONFLICT (policy_id, programme_code) DO UPDATE SET reason = EXCLUDED.reason, closed_at = now()
                """).param("id", policyId).param("code", code).param("reason", reason).update();
    }

    int reopenProgramme(UUID policyId, String code) {
        return jdbc.sql("DELETE FROM admissions.programme_closed WHERE policy_id = :id AND programme_code = :code")
                .param("id", policyId).param("code", code).update();
    }

    boolean facultyExists(String code) {
        return jdbc.sql("SELECT count(*) FROM ref.faculty WHERE code = :c").param("c", code).query(Long.class).single() > 0;
    }

    boolean programmeExists(String code) {
        return jdbc.sql("SELECT count(*) FROM ref.programme WHERE code = :c").param("c", code).query(Long.class).single() > 0;
    }

    /** {@code admissions.put_in_force}: refuses, by name, until the findings are empty and a minute is cited. */
    void putInForce(String session, String instrument) {
        jdbc.sql("SELECT admissions.put_in_force(:s, :i)").param("s", session).param("i", instrument).query().singleRow();
    }

    /** A new draft for {@code to}, carrying everything {@code from} states, so a session begins from the last one. */
    void copy(String from, String to) {
        UUID id = UUID.randomUUID();
        jdbc.sql("""
                INSERT INTO admissions.session_policy
                       (id, session, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, ratio_science, ratio_arts,
                        elg_cap_pct, dept_share_pct, index_prelim_places, index_per_zone, mpf_only, screening_required, state)
                SELECT :id, :to, nuc_quota, weight_utme, weight_putme, ratio_utme, ratio_de, ratio_science, ratio_arts,
                       elg_cap_pct, dept_share_pct, index_prelim_places, index_per_zone, mpf_only, screening_required, 'DRAFT'
                  FROM admissions.session_policy WHERE session = :from
                """).param("id", id).param("to", to).param("from", from).update();
        jdbc.sql("""
                INSERT INTO admissions.selection_criterion (policy_id, criterion, percent)
                SELECT :id, c.criterion, c.percent FROM admissions.selection_criterion c
                  JOIN admissions.session_policy p ON p.id = c.policy_id WHERE p.session = :from
                """).param("id", id).param("from", from).update();
        jdbc.sql("""
                INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff)
                SELECT :id, f.faculty_code, f.quota, f.cutoff FROM admissions.faculty_quota f
                  JOIN admissions.session_policy p ON p.id = f.policy_id WHERE p.session = :from
                """).param("id", id).param("from", from).update();
        jdbc.sql("""
                INSERT INTO admissions.programme_rule
                       (policy_id, programme_code, cutoff, olevel_credits, olevel_sittings, olevel_text, utme_text, de_text)
                SELECT :id, r.programme_code, r.cutoff, r.olevel_credits, r.olevel_sittings, r.olevel_text, r.utme_text, r.de_text
                  FROM admissions.programme_rule r
                  JOIN admissions.session_policy p ON p.id = r.policy_id WHERE p.session = :from
                """).param("id", id).param("from", from).update();
        /* the subject groups come with the rules (V008), so the screening keeps its relevant subjects (V020) */
        jdbc.sql("""
                WITH src AS (
                    SELECT g.id AS old_id, gen_random_uuid() AS new_id, g.programme_code, g.scope, g.choose, g.min_grade
                      FROM admissions.rule_subject_group g
                      JOIN admissions.session_policy p ON p.id = g.policy_id WHERE p.session = :from),
                made AS (
                    INSERT INTO admissions.rule_subject_group (id, policy_id, programme_code, scope, choose, min_grade)
                    SELECT new_id, :id, programme_code, scope, choose, min_grade FROM src RETURNING id)
                INSERT INTO admissions.rule_subject (group_id, subject)
                SELECT s.new_id, rs.subject FROM src s JOIN admissions.rule_subject rs ON rs.group_id = s.old_id
                """).param("id", id).param("from", from).update();
    }
}
