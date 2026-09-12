package ng.edu.moaum.portal.admissions;

import java.util.List;
import java.util.Optional;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class AdmissionCycleRepository {

    private final JdbcClient jdbc;

    AdmissionCycleRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    AdmissionCycle.Counts counts(String session) {
        return jdbc.sql("""
                SELECT (SELECT count(*) FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id
                         WHERE r.session = :s AND b.committed_at IS NOT NULL) AS applications,
                       (SELECT count(*) FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id
                         WHERE r.session = :s AND b.committed_at IS NOT NULL AND r.aggregate IS NOT NULL) AS screened,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = :s AND c.offer_state IN ('ADMITTED','ACCEPTED')) AS offers,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = :s AND c.offer_state = 'ACCEPTED') AS accepted,
                       (SELECT count(*) FROM people.student st WHERE st.entry_session = :s) AS on_the_register,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = :s AND c.offer_state IN ('ADMITTED','ACCEPTED')
                           AND NOT EXISTS (SELECT 1 FROM people.student st WHERE st.candidate_id = c.id)) AS not_yet_on_register
                """).param("s", session).query(AdmissionCycle.Counts.class).single();
    }

    Optional<Integer> capacity(String session) {
        return jdbc.sql("SELECT nuc_quota FROM admissions.session_policy WHERE session = :s").param("s", session)
                .query(Integer.class).optional();
    }

    boolean inForce(String session) {
        return jdbc.sql("SELECT count(*) FROM admissions.session_policy WHERE session = :s AND state = 'IN_FORCE'")
                .param("s", session).query(Long.class).single() > 0;
    }

    List<AdmissionCycle.ProgrammeRow> programmes(String session, boolean inForce) {
        return jdbc.sql("""
                SELECT p.code, p.name, p.faculty_code, f.name AS faculty_name,
                       (SELECT count(*) FROM admissions.caps_row r JOIN admissions.caps_batch b ON b.id = r.batch_id
                         WHERE r.session = :s AND b.committed_at IS NOT NULL AND r.jamb_code = p.code) AS applied,
                       (SELECT r.quota FROM admissions.programme_rule r JOIN admissions.session_policy sp ON sp.id = r.policy_id
                         WHERE sp.session = :s AND r.programme_code = p.code) AS quota,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = :s AND c.programme = p.code
                           AND c.offer_state IN ('ADMITTED','ACCEPTED')) AS offered,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = :s AND c.programme = p.code
                           AND c.offer_state = 'ACCEPTED') AS accepted,
                       CASE WHEN :force THEN admissions.cutoff_for(:s, p.code) END AS cutoff
                  FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT p.archived
                 ORDER BY f.name, p.name
                """).param("s", session).param("force", inForce).query(AdmissionCycle.ProgrammeRow.class).list();
    }
}
