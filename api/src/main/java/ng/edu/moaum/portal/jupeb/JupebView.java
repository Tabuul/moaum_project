package ng.edu.moaum.portal.jupeb;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * One JUPEB candidate as a page reads them (V339): the application and biodata, the programme of interest and the
 * combination with its three subjects, the O'Level and its verdict, the documents (never their bytes), what still stands
 * before submission, the fees as the Bursary's rule computes them and the references paid, the decisions, screening,
 * class, registered subjects, examination number and results. The candidate's own view leaves out the office's working
 * (who decided, the number's correction history) and shows results only once the session's results are published.
 */
@Component
class JupebView {

    private final JdbcClient jdbc;

    JupebView(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    static final String ROW = """
            SELECT a.id, a.session, a.application_no, a.surname, a.first_name, a.middle_name, a.sex, a.date_of_birth::text AS date_of_birth, a.nin, a.email, a.phone,
                   a.nationality, a.state_of_origin, a.lga, a.contact_address, a.permanent_address, a.home_town,
                   a.guardian_name, a.guardian_phone, a.guardian_address, a.next_of_kin_name, a.next_of_kin_phone, a.next_of_kin_relationship,
                   a.programme_code, g.name AS programme_name, d.name AS department_name, f.code AS faculty_code, f.name AS faculty_name,
                   a.combination_id, c.code AS combination_code, c.name AS combination_name, c.area AS combination_area,
                   a.state, a.fee_confirmed_at, a.submitted_at, a.return_note, a.returned_at, a.eligibility_note, a.eligibility_decided_at,
                   a.admission_ref, a.admission_note, a.admission_decided_at, a.activated_at, a.class_id, cl.name AS class_name,
                   a.subjects_registered_at, a.exam_no, a.exam_no_assigned_at,
                   a.screening_state, a.screening_venue, a.screening_at, a.screening_reason, a.screening_decided_at,
                   a.created_at, a.updated_at, a.state IN ('DRAFT', 'RETURNED') AS editable,
                   (SELECT fs.application_fee FROM jupeb.fee_setting_of(a.session) fs) AS application_fee
              FROM jupeb.application a
              LEFT JOIN ref.programme g ON g.code = a.programme_code
              LEFT JOIN ref.department d ON d.code = g.dept_code
              LEFT JOIN ref.faculty f ON f.code = g.faculty_code
              LEFT JOIN jupeb.combination c ON c.id = a.combination_id
              LEFT JOIN jupeb.class cl ON cl.id = a.class_id
            """;

    Map<String, Object> of(UUID app, boolean office) {
        Map<String, Object> a = jdbc.sql(ROW + " WHERE a.id = :id").param("id", app).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("JUPEB application", app));
        Map<String, Object> out = new LinkedHashMap<>(a);
        String session = (String) a.get("session");
        out.put("subjects", jdbc.sql("""
                SELECT s.id, s.code, s.title FROM jupeb.combination c CROSS JOIN LATERAL unnest(ARRAY[c.subject1, c.subject2, c.subject3]) WITH ORDINALITY u(sid, ord)
                  JOIN jupeb.subject s ON s.id = u.sid WHERE c.id = :c ORDER BY u.ord
                """).param("c", a.get("combination_id"), java.sql.Types.OTHER).query().listOfRows());
        out.put("olevel", jdbc.sql("SELECT sitting, exam_type, exam_number, exam_year, subject, grade FROM jupeb.olevel WHERE application_id = :id ORDER BY sitting, subject")
                .param("id", app).query().listOfRows());
        out.put("olevelCheck", jdbc.sql("SELECT * FROM jupeb.olevel_check(:id)").param("id", app).query().singleRow());
        out.put("documents", jdbc.sql("""
                SELECT k.code AS kind, k.label, k.required, k.image, d.id, d.filename, d.content_type, d.size_bytes, d.status, d.review_note, d.reviewed_at, d.uploaded_at
                  FROM jupeb.document_kind k LEFT JOIN jupeb.document d ON d.kind = k.code AND d.application_id = :id
                 WHERE k.active OR d.id IS NOT NULL ORDER BY k.ord, k.label
                """).param("id", app).query().listOfRows());
        out.put("missing", missing(app));
        out.put("fees", jdbc.sql("SELECT * FROM jupeb.school_fees(:id)").param("id", app).query().singleRow());
        out.put("feeRule", jdbc.sql("SELECT application_fee, first_percent, allow_full, activation, indigene_state FROM jupeb.fee_setting_of(:s)").param("s", session).query().singleRow());
        out.put("references", jdbc.sql("""
                SELECT kind, reference, amount, semester, expires_at, confirmed_at, channel, created_at
                  FROM jupeb.fee_reference WHERE application_id = :id ORDER BY created_at DESC
                """).param("id", app).query().listOfRows());
        out.put("screeningSetting", jdbc.sql("SELECT screening_required, screening_venue, screening_starts_on::text AS screening_starts_on, screening_ends_on::text AS screening_ends_on, screening_instructions FROM jupeb.setting_of(:s)")
                .param("s", session).query().singleRow());
        boolean published = jdbc.sql("SELECT jupeb.results_published(:s)").param("s", session).query(Boolean.class).single();
        out.put("resultsPublished", published);
        out.put("registered", jdbc.sql("""
                SELECT s.code, s.title, sr.registered_at, r.grade, r.points
                  FROM jupeb.subject_registration sr JOIN jupeb.subject s ON s.id = sr.subject_id
                  LEFT JOIN jupeb.result r ON r.application_id = sr.application_id AND r.subject_id = sr.subject_id
                 WHERE sr.application_id = :id ORDER BY s.code
                """).param("id", app).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    if (!office && !published) { m.remove("grade"); m.remove("points"); }
                    return m;
                }).toList());
        if (office) {
            out.put("events", jdbc.sql("""
                    SELECT e.kind, e.note, e.at, e.actor_office, p.surname || ', ' || p.given_names AS actor_name
                      FROM jupeb.application_event e LEFT JOIN iam.person p ON p.id = e.actor_id
                     WHERE e.application_id = :id ORDER BY e.at, e.kind
                    """).param("id", app).query().listOfRows());
            out.put("examNoHistory", jdbc.sql("""
                    SELECT x.old_no, x.new_no, x.reason, x.source, x.batch_ref, x.changed_office, x.changed_at, p.surname || ', ' || p.given_names AS changed_by_name
                      FROM jupeb.exam_no_change x LEFT JOIN iam.person p ON p.id = x.changed_by WHERE x.application_id = :id ORDER BY x.changed_at
                    """).param("id", app).query().listOfRows());
            out.put("resultChanges", jdbc.sql("""
                    SELECT s.code, x.old_grade, x.new_grade, x.reason, x.batch_ref, x.changed_at
                      FROM jupeb.result_change x JOIN jupeb.subject s ON s.id = x.subject_id WHERE x.application_id = :id ORDER BY x.changed_at
                    """).param("id", app).query().listOfRows());
            out.put("decidedBy", jdbc.sql("""
                    SELECT (SELECT surname || ', ' || given_names FROM iam.person WHERE id = a.eligibility_decided_by) AS eligibility,
                           (SELECT surname || ', ' || given_names FROM iam.person WHERE id = a.admission_decided_by) AS admission,
                           (SELECT surname || ', ' || given_names FROM iam.person WHERE id = a.returned_by) AS returned,
                           (SELECT surname || ', ' || given_names FROM iam.person WHERE id = a.screening_decided_by) AS screening
                      FROM jupeb.application a WHERE a.id = :id
                    """).param("id", app).query().singleRow());
        } else {
            out.put("events", jdbc.sql("SELECT kind, note, at FROM jupeb.application_event WHERE application_id = :id ORDER BY at, kind")
                    .param("id", app).query().listOfRows());
        }
        return out;
    }

    /** what still stands between the application and its submission */
    List<String> missing(UUID app) {
        return jdbc.sql("SELECT unnest(jupeb.missing(:id))").param("id", app).query(String.class).list();
    }

    /** the approved combinations with their three subjects, for the pickers and the office's list */
    List<Map<String, Object>> combinations(boolean activeOnly) {
        return jdbc.sql("""
                SELECT c.id, c.code, c.name, c.area, c.description, c.eligibility_notes, c.active,
                       s1.code AS subject1_code, s1.title AS subject1, s2.code AS subject2_code, s2.title AS subject2, s3.code AS subject3_code, s3.title AS subject3,
                       (SELECT coalesce(array_agg(coalesce(r.faculty_code, r.programme_code) ORDER BY r.faculty_code NULLS LAST, r.programme_code), '{}')
                          FROM jupeb.combination_relevance r WHERE r.combination_id = c.id) AS leads_to,
                       (SELECT count(*) FROM jupeb.application a WHERE a.combination_id = c.id) AS applications
                  FROM jupeb.combination c
                  JOIN jupeb.subject s1 ON s1.id = c.subject1 JOIN jupeb.subject s2 ON s2.id = c.subject2 JOIN jupeb.subject s3 ON s3.id = c.subject3
                 WHERE c.active OR NOT :active
                 ORDER BY c.code
                """).param("active", activeOnly).query().listOfRows();
    }
}
