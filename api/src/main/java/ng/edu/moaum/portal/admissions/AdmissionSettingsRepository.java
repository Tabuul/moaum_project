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
                SELECT g.code, g.name, g.faculty_code, f.name AS faculty_name, r.cutoff, r.olevel_text, r.utme_text,
                       r.de_text, r.olevel_credits, r.olevel_sittings, (r.programme_code IS NOT NULL) AS stated
                  FROM ref.programme g
                  JOIN ref.faculty f ON f.code = g.faculty_code
                  LEFT JOIN (SELECT r.* FROM admissions.programme_rule r
                               JOIN admissions.session_policy p ON p.id = r.policy_id
                              WHERE p.session = :session) r ON r.programme_code = g.code
                 ORDER BY f.name, g.name
                """)
                .param("session", session)
                .query(AdmissionPolicy.ProgrammeRule.class)
                .list();
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

    void upsertFacultyQuota(UUID policyId, String facultyCode, Integer quota, Integer cutoff) {
        jdbc.sql("""
                INSERT INTO admissions.faculty_quota (policy_id, faculty_code, quota, cutoff) VALUES (:id, :f, :q, :k)
                ON CONFLICT (policy_id, faculty_code) DO UPDATE SET quota = EXCLUDED.quota, cutoff = EXCLUDED.cutoff
                """)
                .param("id", policyId).param("f", facultyCode)
                .param("q", quota, Types.INTEGER).param("k", cutoff, Types.INTEGER)
                .update();
    }

    void upsertProgrammeRule(UUID policyId, String code, AdmissionSettingsService.ProgrammeRuleIn r) {
        jdbc.sql("""
                INSERT INTO admissions.programme_rule
                       (policy_id, programme_code, cutoff, olevel_credits, olevel_sittings, olevel_text, utme_text, de_text)
                VALUES (:id, :code, :cutoff, :credits, :sittings, :olevel, :utme, :de)
                ON CONFLICT (policy_id, programme_code) DO UPDATE SET
                        cutoff = EXCLUDED.cutoff, olevel_credits = EXCLUDED.olevel_credits,
                        olevel_sittings = EXCLUDED.olevel_sittings, olevel_text = EXCLUDED.olevel_text,
                        utme_text = EXCLUDED.utme_text, de_text = EXCLUDED.de_text
                """)
                .param("id", policyId).param("code", code)
                .param("cutoff", r.cutoff(), Types.INTEGER)
                .param("credits", r.olevelCredits() == null ? 5 : r.olevelCredits())
                .param("sittings", r.olevelSittings() == null ? 2 : r.olevelSittings())
                .param("olevel", r.olevelText().trim())
                .param("utme", r.utmeText().trim())
                .param("de", r.deText().trim())
                .update();
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
    }
}
