package ng.edu.moaum.portal.iam;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/**
 * The counts the menu carries beside its items: what is actually waiting in
 * each queue, keyed by the prototype's menu item id, and nothing where
 * nothing waits. One query, all scalar counts, against the current session
 * where the item is a session's business.
 *
 * "!" marks an item that needs an act before the session can proceed,
 * exactly as the prototype draws it; a number is the queue's length.
 */
@Repository
class WaitingRepository {

    private final JdbcClient jdbc;

    WaitingRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Map<String, String> waiting() {
        Map<String, Object> row = jdbc.sql("""
                WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT')
                SELECT
                  (SELECT count(*) FROM people.biodata_change WHERE state = 'PENDING') AS biochange,
                  (SELECT count(*) FROM admissions.candidate c, cur
                     WHERE c.session = cur.name AND c.offer_state IN ('ADMITTED','ACCEPTED')
                       AND NOT EXISTS (SELECT 1 FROM people.student st WHERE st.candidate_id = c.id)) AS admissions,
                  -- admission settings belong to the intake session (the next planned one), not the
                  -- current session: students are admitted INTO the coming session while the current
                  -- one runs. Flag when that intake session has no policy in force yet.
                  (SELECT NOT EXISTS (SELECT 1 FROM admissions.session_policy p
                                       WHERE p.session = nx.name AND p.in_force IS NOT NULL)
                     FROM (SELECT name FROM policy.academic_session
                            WHERE state = 'PLANNED' ORDER BY starts_on LIMIT 1) nx) AS settings_wanted,
                  EXISTS (SELECT 1 FROM people.student st, cur
                     WHERE st.entry_session = cur.name AND st.matric_no IS NULL AND st.status = 'ADMITTED') AS matriculation_wanted,
                  (SELECT count(*) FROM credentials.transcript_request WHERE stage = 'HELD_AT_CLEARANCE') AS clearance,
                  (SELECT count(*) FROM credentials.transcript_request WHERE stage <> 'RELEASED') AS transcripts,
                  (SELECT count(*) FROM credentials.certificate WHERE status = 'PRINTED') AS certificates,
                  (SELECT count(*) FROM assessment.score_sheet s JOIN assessment.exam_session e ON e.id = s.exam_session_id, cur
                     WHERE e.session = cur.name AND s.stage NOT IN ('ENTRY','PUBLISHED')) AS approvals,
                  (SELECT count(*) FROM iam.person p WHERE p.ended_on IS NULL
                     AND NOT EXISTS (SELECT 1 FROM iam.credential c WHERE c.person_id = p.id)) AS users
                """).query().singleRow();
        Map<String, String> out = new LinkedHashMap<>();
        count(out, "t/biochange", row.get("biochange"));
        count(out, "t/admissions", row.get("admissions"));
        flag(out, "t/admissionsetup", row.get("settings_wanted"));
        flag(out, "t/matriculation", row.get("matriculation_wanted"));
        count(out, "t/clearance", row.get("clearance"));
        count(out, "t/transcripts", row.get("transcripts"));
        count(out, "t/certificates", row.get("certificates"));
        count(out, "t/approvals", row.get("approvals"));
        count(out, "t/users", row.get("users"));
        return out;
    }

    private static void count(Map<String, String> out, String item, Object n) {
        long value = n instanceof Number number ? number.longValue() : 0;
        if (value > 0) out.put(item, Long.toString(value));
    }

    private static void flag(Map<String, String> out, String item, Object wanted) {
        if (Boolean.TRUE.equals(wanted)) out.put(item, "!");
    }
}
