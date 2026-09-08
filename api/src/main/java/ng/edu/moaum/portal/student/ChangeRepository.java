package ng.edu.moaum.portal.student;

import java.sql.Types;
import java.util.List;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

/** The Registry's queue: the requests that wait on evidence, and what was decided on each. */
@Repository
class ChangeRepository {

    private final JdbcClient jdbc;

    ChangeRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    List<BiodataChangeRow> queue(String state) {
        return jdbc.sql("""
                SELECT c.id, c.student_id, s.surname, s.other_names, s.matric_no, s.admission_no,
                       c.field, coalesce(f.label, c.field) AS label, c.from_value, c.to_value,
                       c.evidence, c.requested_at, c.state, c.decision, c.decided_at
                  FROM people.biodata_change c
                  JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.biodata_field f ON f.field = c.field
                 WHERE (CAST(:state AS text) IS NULL OR c.state = CAST(:state AS text))
                 ORDER BY CASE WHEN c.state IN ('PENDING', 'EVIDENCE_ASKED') THEN 0 ELSE 1 END, c.requested_at
                """).param("state", state, Types.VARCHAR).query(BiodataChangeRow.class).list();
    }

    /**
     * The tiles. The oldest request is counted in days because a request that
     * simply sits unanswered is the failure this queue exists to prevent;
     * the self-service figure is every field a student has kept current
     * without asking anybody.
     */
    BiodataChangeRow.Counts counts() {
        return jdbc.sql("""
                SELECT count(*) FILTER (WHERE state IN ('PENDING', 'EVIDENCE_ASKED'))::int AS pending,
                       coalesce(max(CASE WHEN state IN ('PENDING', 'EVIDENCE_ASKED')
                                         THEN current_date - requested_at::date END), 0)::int AS oldest_days,
                       count(*) FILTER (WHERE state = 'APPROVED')::int AS approved,
                       count(*) FILTER (WHERE state = 'REFUSED')::int AS refused,
                       (SELECT count(*) FROM people.biodata)::int AS self_service
                  FROM people.biodata_change
                """).query(BiodataChangeRow.Counts.class).single();
    }

    Optional<BiodataChangeRow> one(UUID id) {
        return jdbc.sql("""
                SELECT c.id, c.student_id, s.surname, s.other_names, s.matric_no, s.admission_no,
                       c.field, coalesce(f.label, c.field) AS label, c.from_value, c.to_value,
                       c.evidence, c.requested_at, c.state, c.decision, c.decided_at
                  FROM people.biodata_change c
                  JOIN people.student s ON s.id = c.student_id
                  LEFT JOIN ref.biodata_field f ON f.field = c.field
                 WHERE c.id = :id
                   FOR NO KEY UPDATE OF c
                """).param("id", id).query(BiodataChangeRow.class).optional();
    }

    /** A decision is the state, the officer and the words: the database refuses a blank one. */
    void decide(UUID id, String state, String decision) {
        jdbc.sql("""
                UPDATE people.biodata_change
                   SET state = :state, decision = :decision, decided_at = now(),
                       decided_by = nullif(current_setting('moaum.actor_id', true), '')::uuid
                 WHERE id = :id
                """).param("id", id).param("state", state).param("decision", decision).update();
    }

    void askForEvidence(UUID id) {
        jdbc.sql("UPDATE people.biodata_change SET state = 'EVIDENCE_ASKED' WHERE id = :id")
                .param("id", id).update();
    }
}
