package ng.edu.moaum.portal.health;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class HealthRepository {

    private final JdbcClient jdbc;

    HealthRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /* ── the student ── */

    Optional<Map<String, Object>> profile(UUID student) {
        return jdbc.sql("SELECT blood_group, genotype, allergies, consented_at, restricted_at, fitness, fitness_on FROM health.profile WHERE student_id = :s")
                .param("s", student).query().listOfRows().stream().findFirst();
    }

    List<Map<String, Object>> appointments(UUID student) {
        return jdbc.sql("SELECT id, reason, preferred_at, booked_at, state, cancelled_why FROM health.appointment WHERE student_id = :s ORDER BY preferred_at DESC LIMIT 20")
                .param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> visits(UUID student) {
        return jdbc.sql("SELECT * FROM health.student_visits(:s)").param("s", student).query().listOfRows();
    }

    List<Map<String, Object>> accessLog(UUID student) {
        return jdbc.sql("""
                SELECT a.at, a.what, a.office, p.surname || ', ' || p.given_names AS who
                  FROM health.record_access a LEFT JOIN iam.person p ON p.id = a.person_id
                 WHERE a.student_id = :s ORDER BY a.at DESC LIMIT 50
                """).param("s", student).query().listOfRows();
    }

    UUID book(UUID student, String reason, OffsetDateTime preferred) {
        return jdbc.sql("SELECT health.book(:s, :r, :p)").param("s", student).param("r", reason).param("p", preferred).query(UUID.class).single();
    }

    void cancel(UUID appointment, UUID student, String why) {
        jdbc.sql("SELECT health.cancel(:a, :s, :w)").param("a", appointment).param("s", student).param("w", why, Types.VARCHAR).query().singleRow();
    }

    void consent(UUID student, String blood, String genotype, String allergies) {
        jdbc.sql("SELECT health.consent(:s, :b, :g, :a)").param("s", student).param("b", blood, Types.VARCHAR).param("g", genotype, Types.VARCHAR)
                .param("a", allergies, Types.VARCHAR).query().singleRow();
    }

    void restrict(UUID student) {
        jdbc.sql("SELECT health.restrict(:s)").param("s", student).query().singleRow();
    }

    /* ── the clinic ── */

    Map<String, Object> tiles() {
        return jdbc.sql("""
                SELECT (SELECT count(*) FROM health.visit WHERE arrived_at::date = current_date) AS encounters_today,
                       (SELECT count(*) FROM health.visit WHERE state = 'WAITING') AS waiting,
                       (SELECT coalesce(max(extract(epoch FROM now() - arrived_at) / 60), 0)::int FROM health.visit WHERE state = 'WAITING') AS longest_wait_min,
                       (SELECT count(*) FROM health.visit WHERE referred_to IS NOT NULL AND concluded_at >= date_trunc('month', now())) AS referrals_month,
                       (SELECT count(*) FROM health.profile WHERE fitness <> 'PENDING') AS fitness_recorded,
                       (SELECT count(*) FROM health.appointment WHERE state = 'BOOKED' AND preferred_at::date = current_date) AS booked_today
                """).query().singleRow();
    }

    List<Map<String, Object>> waiting() {
        return jdbc.sql("""
                SELECT v.id, v.arrived_at, v.presenting, v.triage, v.state, v.seen_at, st.id AS student_id,
                       st.surname || ', ' || st.other_names AS patient, coalesce(st.matric_no, st.admission_no) AS number,
                       p.surname || ', ' || p.given_names AS clinician
                  FROM health.visit v JOIN people.student st ON st.id = v.student_id LEFT JOIN iam.person p ON p.id = v.clinician_id
                 WHERE v.state IN ('WAITING','IN_CONSULTATION')
                 ORDER BY CASE v.triage WHEN 'URGENT' THEN 0 WHEN 'STANDARD' THEN 1 ELSE 2 END, v.arrived_at
                """).query().listOfRows();
    }

    List<Map<String, Object>> bookedToday() {
        return jdbc.sql("""
                SELECT a.id, a.reason, a.preferred_at, a.state, st.id AS student_id, st.surname || ', ' || st.other_names AS patient,
                       coalesce(st.matric_no, st.admission_no) AS number
                  FROM health.appointment a JOIN people.student st ON st.id = a.student_id
                 WHERE a.state = 'BOOKED' AND a.preferred_at::date <= current_date + 1
                 ORDER BY a.preferred_at
                """).query().listOfRows();
    }

    List<Map<String, Object>> concludedToday() {
        return jdbc.sql("""
                SELECT v.id, v.concluded_at, v.presenting, v.outcome, v.referred_to, st.surname || ', ' || st.other_names AS patient,
                       coalesce(st.matric_no, st.admission_no) AS number, p.surname || ', ' || p.given_names AS clinician
                  FROM health.visit v JOIN people.student st ON st.id = v.student_id LEFT JOIN iam.person p ON p.id = v.clinician_id
                 WHERE v.state = 'DONE' AND v.concluded_at::date = current_date ORDER BY v.concluded_at DESC
                """).query().listOfRows();
    }

    Optional<Map<String, Object>> patron(String number) {
        return jdbc.sql("""
                SELECT st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name, p.name AS programme
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code
                 WHERE upper(st.matric_no) = upper(:n) OR upper(st.admission_no) = upper(:n)
                """).param("n", number).query().listOfRows().stream().findFirst();
    }

    UUID arrive(UUID student, String presenting, String triage, UUID appointment) {
        return jdbc.sql("SELECT health.arrive(:s, :p, :t, :a)").param("s", student).param("p", presenting, Types.VARCHAR).param("t", triage, Types.VARCHAR)
                .param("a", appointment, Types.OTHER).query(UUID.class).single();
    }

    void see(UUID visit, UUID clinician) {
        jdbc.sql("SELECT health.see(:v, :c)").param("v", visit).param("c", clinician).query().singleRow();
    }

    void conclude(UUID visit, UUID clinician, String outcome, String referred, String note, String fitness) {
        jdbc.sql("SELECT health.conclude(:v, :c, :o, :r, :n, :f)").param("v", visit).param("c", clinician).param("o", outcome)
                .param("r", referred, Types.VARCHAR).param("n", note, Types.VARCHAR).param("f", fitness, Types.VARCHAR).query().singleRow();
    }

    /** the record the clinician opens: the visit, the consented facts, the earlier outcomes and notes — and the opening is logged */
    Map<String, Object> open(UUID visit, UUID clinician, String office) {
        Map<String, Object> v = jdbc.sql("""
                SELECT v.id, v.student_id, v.arrived_at, v.presenting, v.triage, v.state, v.seen_at, v.outcome, v.referred_to,
                       st.surname || ', ' || st.other_names AS patient, coalesce(st.matric_no, st.admission_no) AS number, st.sex, st.date_of_birth, pr.name AS programme
                  FROM health.visit v JOIN people.student st ON st.id = v.student_id JOIN ref.programme pr ON pr.code = st.programme_code WHERE v.id = :v
                """).param("v", visit).query().singleRow();
        UUID student = (UUID) v.get("student_id");
        jdbc.sql("INSERT INTO health.record_access (student_id, person_id, office, what) VALUES (:s, :p, :o, 'read the record')")
                .param("s", student).param("p", clinician).param("o", office).update();
        v.put("profile", profile(student).orElse(null));
        v.put("history", jdbc.sql("""
                SELECT x.id, x.arrived_at, x.presenting, x.outcome, x.referred_to, x.concluded_at, p.surname || ', ' || p.given_names AS clinician,
                       (SELECT string_agg(n.note, E'\\n' ORDER BY n.written_at) FROM health.note n WHERE n.visit_id = x.id) AS notes
                  FROM health.visit x LEFT JOIN iam.person p ON p.id = x.clinician_id
                 WHERE x.student_id = :s AND x.id <> :v AND x.state = 'DONE' ORDER BY x.arrived_at DESC LIMIT 20
                """).param("s", student).param("v", visit).query().listOfRows());
        return v;
    }
}
