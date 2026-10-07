package ng.edu.moaum.portal.jupeb;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * One JUPEB candidate as a page reads them (V339, V342): the application and biodata, the programme (Science or Non-Science)
 * and the combination with its three subjects, the O'Level and its verdict, the documents (never their bytes) — the O'Level
 * result once for each sitting — the guided application's steps, the fees as the Bursary's rule computes them and the
 * references paid, admission status checking and acceptance, screening, class, registered subjects, examination number,
 * results and the grade point.
 *
 * The candidate's own view leaves out the office's working (who decided, the number's correction history), shows results
 * only once the session's results are published, and — until the candidate may read their admission status (the checking
 * fee paid while checking is open, or accepted) — shows a decided application as under review, without the decision.
 */
@Component
class JupebView {

    /** the states a decision has been taken in: hidden from the candidate until they may check their status */
    static final Set<String> DECIDED = Set.of("ELIGIBLE", "INELIGIBLE", "PENDING", "ADMITTED", "NOT_ADMITTED");
    /** the change requests made after submission, newest first (V343) */
    List<Map<String, Object>> requests(UUID app) {
        return jdbc.sql("""
                SELECT r.id, r.kind, r.state, jupeb.change_words(r.id) AS words, r.reason, r.requested_at, r.requested_office, r.decided_at, r.decided_office,
                       r.decision_note, r.to_stream, tc.code AS to_combination_code, r.from_session, r.to_session,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = r.decided_by) AS decided_by_name
                  FROM jupeb.change_request r LEFT JOIN jupeb.combination tc ON tc.id = r.to_combination
                 WHERE r.application_id = :id ORDER BY r.requested_at DESC
                """).param("id", app).query().listOfRows();
    }

    /** the papers issued with a verification code, and whether each still states the record (V343) */
    List<Map<String, Object>> papers(UUID app) {
        return jdbc.sql("""
                SELECT p.code, p.kind, p.subject_ref, p.issued_at, p.issued_office, p.revoked_at, p.revoked_reason,
                       p.revoked_at IS NULL AND md5(coalesce(jupeb.paper_facts(p.application_id, p.kind, p.subject_ref, true), 'null'::jsonb)::text) = p.fingerprint AS current
                  FROM jupeb.paper p WHERE p.application_id = :id ORDER BY p.issued_at DESC
                """).param("id", app).query().listOfRows();
    }

    /** the trail's entries that would tell the decision */
    private static final Set<String> DECISION_EVENTS = Set.of("ELIGIBLE", "INELIGIBLE", "PENDING", "ADMITTED", "NOT_ADMITTED");

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    JupebView(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    static final String ROW = """
            SELECT a.id, a.session, a.application_no, a.surname, a.first_name, a.middle_name, a.sex, a.date_of_birth::text AS date_of_birth, a.nin, a.email, a.phone,
                   a.nationality, a.state_of_origin, a.lga, a.contact_address, a.permanent_address, a.home_town,
                   a.guardian_name, a.guardian_phone, a.guardian_address, a.next_of_kin_name, a.next_of_kin_phone, a.next_of_kin_relationship,
                   a.stream, a.programme_code, g.name AS programme_name, d.name AS department_name, f.code AS faculty_code, f.name AS faculty_name,
                   a.combination_id, c.code AS combination_code, c.name AS combination_name, c.area AS combination_area,
                   a.state, a.fee_confirmed_at, a.submitted_at, a.return_note, a.returned_at, a.eligibility_note, a.eligibility_decided_at,
                   a.admission_ref, a.admission_note, a.admission_decided_at, a.activated_at, a.class_id, cl.name AS class_name,
                   a.subjects_registered_at, a.exam_no, a.exam_no_assigned_at, a.olevel_sittings,
                   a.screening_state, a.screening_venue, a.screening_at, a.screening_reason, a.screening_decided_at,
                   a.created_at, a.updated_at, a.state IN ('DRAFT', 'RETURNED') AS editable,
                   (SELECT fs.application_fee FROM jupeb.fee_setting_of(a.session) fs) AS application_fee,
                   jupeb.paid_at(a.id, 'STATUS_CHECKING') AS checking_paid_at, jupeb.paid_at(a.id, 'ACCEPTANCE') AS accepted_at,
                   EXISTS (SELECT 1 FROM jupeb.document p WHERE p.application_id = a.id AND p.kind = 'PASSPORT') AS has_passport,
                   a.withdrawn_at, a.deferred_from, a.deferred_to, a.legacy_source, a.legacy_ref, a.legacy_batch,
                   (SELECT acc.must_change_password FROM jupeb.account acc WHERE acc.id = a.account_id) AS must_change_password
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
        out.put("documents", documents(app));
        out.put("steps", parse(jdbc.sql("SELECT jupeb.step_status(:id)::text").param("id", app).query(String.class).single()));
        out.put("missing", missing(app));
        out.put("fees", jdbc.sql("SELECT * FROM jupeb.school_fees(:id)").param("id", app).query().singleRow());
        out.put("feeRule", jdbc.sql("SELECT application_fee, checking_fee, acceptance_fee, first_percent, allow_full, activation, indigene_state FROM jupeb.fee_setting_of(:s)")
                .param("s", session).query().singleRow());
        out.put("references", jdbc.sql("""
                SELECT kind, reference, amount, semester, expires_at, confirmed_at, channel, created_at
                  FROM jupeb.fee_reference WHERE application_id = :id ORDER BY created_at DESC
                """).param("id", app).query().listOfRows());
        Map<String, Object> checking = jdbc.sql("SELECT * FROM jupeb.status_checking(:id)").param("id", app).query().singleRow();
        out.put("statusChecking", checking);
        out.put("screeningSetting", jdbc.sql("""
                SELECT screening_required, screening_venue, screening_starts_on::text AS screening_starts_on, screening_ends_on::text AS screening_ends_on,
                       screening_instructions, exam_month
                  FROM jupeb.setting_of(:s)
                """).param("s", session).query().singleRow());
        boolean published = jdbc.sql("SELECT jupeb.results_published(:s)").param("s", session).query(Boolean.class).single();
        out.put("resultsPublished", published);
        out.put("registered", jdbc.sql("""
                SELECT s.id AS subject_id, s.code, s.title, sr.registered_at, r.grade, r.points, sr.board_subject_id,
                       (SELECT b.title || ' (' || b.prefix || ')' FROM jupeb.board_subject b WHERE b.id = sr.board_subject_id) AS option_title,
                       (SELECT CASE WHEN count(*) > 1 THEN jsonb_agg(jsonb_build_object('id', b.id, 'code', b.code, 'prefix', b.prefix, 'title', b.title) ORDER BY b.code)::text END
                          FROM jupeb.board_subject b WHERE b.subject_id = s.id) AS options,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('id', u.unit_id, 'code', u.code, 'title', u.title, 'semester', u.semester, 'credit_units', u.credit_units,
                                                                     'topics', u.topics) ORDER BY u.semester NULLS LAST, u.board_code NULLS LAST, u.ord, u.code), '[]'::jsonb)::text
                          FROM jupeb.units_for((SELECT x.combination_id FROM jupeb.application x WHERE x.id = :id), :id) u WHERE u.subject_id = s.id) AS units
                  FROM jupeb.subject_registration sr JOIN jupeb.subject s ON s.id = sr.subject_id
                  LEFT JOIN jupeb.result r ON r.application_id = sr.application_id AND r.subject_id = sr.subject_id
                 WHERE sr.application_id = :id ORDER BY s.title
                """).param("id", app).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("units", parse(String.valueOf(r.get("units"))));
                    m.put("options", r.get("options") == null ? null : parse(String.valueOf(r.get("options"))));
                    if (!office && !published) { m.remove("grade"); m.remove("points"); }
                    return m;
                }).toList());
        if (office || published) {
            out.put("gradePoint", jdbc.sql("SELECT * FROM jupeb.grade_point(:id)").param("id", app).query().singleRow());
        }
        out.put("requests", requests(app));
        /* V350: the refund claim a withdrawal opened, with the refunds raised on it — the account number never whole here */
        out.put("refundClaim", jdbc.sql("""
                SELECT c.id, c.opened_at, c.payments::text AS payments, c.paid_total, c.bank_name, c.account_name,
                       CASE WHEN c.account_number IS NULL THEN NULL ELSE '••••••' || right(c.account_number, 4) END AS account_number,
                       c.details_at, c.declined_at, c.declined_reason, jupeb.refund_claim_state(c.id)::text AS state,
                       (SELECT coalesce(jsonb_agg(jsonb_build_object('reference', f.reference, 'source', x.reference, 'amount', f.amount, 'state', f.state,
                                                                     'proposedAt', f.proposed_at, 'paidAt', f.paid_at) ORDER BY f.proposed_at), '[]'::jsonb)::text
                          FROM jupeb.refund_claim_refund x JOIN finance.refund f ON f.id = x.refund_id WHERE x.claim_id = c.id) AS refunds
                  FROM jupeb.refund_claim c WHERE c.application_id = :id
                """).param("id", app).query().listOfRows().stream().findFirst().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("payments", parse(String.valueOf(r.get("payments"))));
                    m.put("state", parse(String.valueOf(r.get("state"))));
                    m.put("refunds", parse(String.valueOf(r.get("refunds"))));
                    return (Object) m;
                }).orElse(null));
        /* V349: the notices that reach the candidate and are not yet opened, for the side menu */
        if (!office) {
            out.put("unreadAnnouncements", jdbc.sql("""
                    SELECT count(*) FROM jupeb.announcement n JOIN jupeb.application a ON a.id = :id
                     WHERE n.withdrawn_at IS NULL AND (n.expires_on IS NULL OR n.expires_on >= (now() AT TIME ZONE 'Africa/Lagos')::date)
                       AND jupeb.audience_reaches(n.session, n.audience, n.audience_ref, a)
                       AND NOT EXISTS (SELECT 1 FROM jupeb.announcement_read r WHERE r.announcement_id = n.id AND r.application_id = a.id)
                    """).param("id", app).query(Integer.class).single());
        }
        /* V344: the attendance standing, subject by subject, once a student */
        out.put("attendanceStanding", List.of("STUDENT", "COMPLETED").contains(String.valueOf(a.get("state"))) ? jdbc.sql("""
                SELECT m.semester, s.code, s.title, m.total, m.counted, m.absent, m.rate, m.min_percent, m.verdict, m.at_risk, m.warnable
                  FROM attendance.member_summary('JUPEB', :id, :s) m JOIN jupeb.subject s ON s.id = m.subject_ref ORDER BY s.title, m.semester
                """).param("id", app).param("s", session).query().listOfRows() : List.of());
        if (office) {
            /* V350: the student's practice attempts, for the JUPEB Office's advice */
            out.put("practice", jdbc.sql("""
                    SELECT t.title, s.code, s.title AS subject, p.number, p.submitted_at, p.score, p.total, p.percentage
                      FROM jupeb.practice_attempt p JOIN jupeb.practice_test t ON t.id = p.test_id JOIN jupeb.subject s ON s.id = t.subject_id
                     WHERE p.application_id = :id AND p.submitted_at IS NOT NULL ORDER BY p.submitted_at DESC LIMIT 200
                    """).param("id", app).query().listOfRows());
            out.put("papers", papers(app));
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
            return out;
        }
        List<Map<String, Object>> events = jdbc.sql("SELECT kind, note, at FROM jupeb.application_event WHERE application_id = :id ORDER BY at, kind")
                .param("id", app).query().listOfRows();
        boolean mayCheck = Boolean.TRUE.equals(checking.get("may_check"));
        if (!mayCheck && DECIDED.contains(String.valueOf(a.get("state")))) {
            // the decision is the applicant's to read only by checking their status: until then the application is under review
            out.put("state", "UNDER_REVIEW");
            for (String k : List.of("eligibility_note", "eligibility_decided_at", "admission_ref", "admission_note", "admission_decided_at",
                    "screening_state", "screening_venue", "screening_at", "screening_reason", "screening_decided_at")) out.put(k, null);
            out.remove("fees");
            events = events.stream().filter(e -> {
                String k = String.valueOf(e.get("kind"));
                return !DECISION_EVENTS.contains(k) && !k.startsWith("SCREENING_");
            }).toList();
        }
        out.put("events", events);
        return out;
    }

    /** the documents of an application: each required one (the O'Level result once a declared sitting), the optional kinds, and any other on file */
    List<Map<String, Object>> documents(UUID app) {
        return jdbc.sql("""
                WITH want AS (
                    SELECT q.kind, q.sitting, q.label, q.ord, true AS required FROM jupeb.required_documents(:id) q
                    UNION ALL
                    SELECT k.code, NULL::int, k.label, k.ord, false FROM jupeb.document_kind k WHERE k.active AND NOT k.required
                    UNION ALL
                    SELECT d.kind, d.sitting, k.label || coalesce(CASE d.sitting WHEN 1 THEN ' — first sitting' WHEN 2 THEN ' — second sitting' END, ''), k.ord, false
                      FROM jupeb.document d JOIN jupeb.document_kind k ON k.code = d.kind
                     WHERE d.application_id = :id
                       AND NOT EXISTS (SELECT 1 FROM jupeb.required_documents(:id) q WHERE q.kind = d.kind AND coalesce(q.sitting, 0) = coalesce(d.sitting, 0))
                       AND NOT (NOT k.required AND k.active AND d.sitting IS NULL))
                SELECT w.kind, w.sitting, w.label, w.required, k.image, d.id, d.filename, d.content_type, d.size_bytes, d.status, d.review_note, d.reviewed_at,
                       d.uploaded_at, d.exam_body, d.exam_year
                  FROM want w JOIN jupeb.document_kind k ON k.code = w.kind
                  LEFT JOIN jupeb.document d ON d.application_id = :id AND d.kind = w.kind AND coalesce(d.sitting, 0) = coalesce(w.sitting, 0)
                 ORDER BY w.ord, w.sitting NULLS FIRST, w.label
                """).param("id", app).query().listOfRows();
    }

    private Object parse(String text) {
        return text == null ? null : json.readValue(text, Object.class);
    }

    private static final tools.jackson.databind.ObjectMapper READER = new tools.jackson.databind.ObjectMapper();

    /** a jsonb column read as text, as plain maps and lists, for the other JUPEB controllers (V350) */
    /** V356: every session of a JUPEB account ended — after its password changes — but the one in use, when one is given */
    static int endSessions(JdbcClient jdbc, UUID account, String keepSidHex, String reason) {
        byte[] keep = null;
        if (keepSidHex != null && !keepSidHex.isBlank()) {
            try { keep = java.util.HexFormat.of().parseHex(keepSidHex); } catch (IllegalArgumentException notHex) { keep = null; }
        }
        return jdbc.sql("""
                UPDATE platform.session SET ended_at = now(), ended_reason = :r
                 WHERE ended_at IS NULL AND person_id IN (SELECT id FROM jupeb.application WHERE account_id = :acc) AND (CAST(:keep AS bytea) IS NULL OR id <> CAST(:keep AS bytea))
                """).param("r", reason).param("acc", account).param("keep", keep, java.sql.Types.BINARY).update();
    }

    static Object readJson(String text) {
        return text == null || "null".equals(text) ? null : READER.readValue(text, Object.class);
    }

    /** V353: a course unit's syllabus — the unit, its objectives, its subject's general objectives and the topics in the order printed */
    static Map<String, Object> unitSyllabus(org.springframework.jdbc.core.simple.JdbcClient jdbc, UUID unit) {
        Map<String, Object> out = new LinkedHashMap<>(jdbc.sql("""
                SELECT u.id, u.code, u.title, u.semester, u.credit_units, u.objectives, u.source_page, s.code AS subject_code, s.title AS subject_title,
                       b.code AS board_code, b.title AS board_title, b.prefix, b.objectives AS subject_objectives, y.title AS syllabus
                  FROM jupeb.subject_unit u JOIN jupeb.subject s ON s.id = u.subject_id
                  LEFT JOIN jupeb.board_subject b ON b.id = u.board_subject_id LEFT JOIN jupeb.syllabus y ON y.id = b.syllabus_id
                 WHERE u.id = :u
                """).param("u", unit).query().listOfRows().stream().findFirst().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course unit", unit)));
        out.put("topics", jdbc.sql("SELECT ord, sn, topic, sub_topic, details, source_page FROM jupeb.unit_topic WHERE unit_id = :u ORDER BY ord")
                .param("u", unit).query().listOfRows());
        return out;
    }

    /** V355: a subject's continuous-assessment sheet for a session (one class, or all): the parts and their maxima, each student's scores,
     *  the total and whether complete, and the subject's lock */
    static Map<String, Object> caSheet(org.springframework.jdbc.core.simple.JdbcClient jdbc, String session, UUID subject, UUID klass) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("subject", jdbc.sql("SELECT id, code, title FROM jupeb.subject WHERE id = :s").param("s", subject).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new NotFound("JUPEB subject", subject)));
        out.put("components", jdbc.sql("SELECT id, code, title, max_score, ord FROM jupeb.ca_component WHERE session = :s AND active ORDER BY ord, code").param("s", session).query().listOfRows());
        out.put("lock", jdbc.sql("""
                SELECT l.locked_at, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = l.locked_by) AS locked_by
                  FROM jupeb.ca_lock l WHERE l.session = :s AND l.subject_id = :sub AND l.unlocked_at IS NULL
                """).param("s", session).param("sub", subject).query().listOfRows().stream().findFirst().orElse(null));
        out.put("unlocks", jdbc.sql("""
                SELECT l.unlocked_at, l.unlock_reason, (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = l.unlocked_by) AS unlocked_by
                  FROM jupeb.ca_lock l WHERE l.session = :s AND l.subject_id = :sub AND l.unlocked_at IS NOT NULL ORDER BY l.unlocked_at DESC
                """).param("s", session).param("sub", subject).query().listOfRows());
        out.put("rows", jdbc.sql("""
                SELECT application_id, application_no, name, class_name, exam_no, scores::text AS scores, total, out_of, complete
                  FROM jupeb.ca_sheet(:s, :sub, :k)
                """).param("s", session).param("sub", subject).param("k", klass, java.sql.Types.OTHER).query().listOfRows().stream().map(r -> {
                    Map<String, Object> m = new LinkedHashMap<>(r);
                    m.put("scores", readJson(String.valueOf(r.get("scores"))));
                    return m;
                }).toList());
        return out;
    }

    /** what still stands between the application and its submission */
    List<String> missing(UUID app) {
        return jdbc.sql("SELECT unnest(jupeb.missing(:id))").param("id", app).query(String.class).list();
    }

    /** the combinations the University offers, each saying whether it suits Science and Non-Science: the applicant's picker
     *  filters by the programme chosen on the page, the student's by their own (V341, V342) */
    List<Map<String, Object>> combinationsFor(UUID app) {
        return combinations(true);
    }

    /** the approved combinations with their three subjects, for the pickers and the office's list */
    List<Map<String, Object>> combinations(boolean activeOnly) {
        return jdbc.sql("""
                SELECT c.id, c.code, c.name, c.area, c.description, c.eligibility_notes, c.active,
                       s1.code AS subject1_code, s1.title AS subject1, s2.code AS subject2_code, s2.title AS subject2, s3.code AS subject3_code, s3.title AS subject3,
                       (SELECT coalesce(array_agg(coalesce(r.faculty_code, r.programme_code) ORDER BY r.faculty_code NULLS LAST, r.programme_code), '{}')
                          FROM jupeb.combination_relevance r WHERE r.combination_id = c.id) AS leads_to,
                       (SELECT count(*) FROM jupeb.application a WHERE a.combination_id = c.id) AS applications,
                       c.active AND s1.active AND s2.active AND s3.active AS offered,
                       array_remove(ARRAY[CASE WHEN NOT s1.active THEN s1.code END, CASE WHEN NOT s2.active THEN s2.code END, CASE WHEN NOT s3.active THEN s3.code END], NULL) AS subjects_not_offered,
                       jupeb.combination_suits(c.area, 'SCIENCE') AS science, jupeb.combination_suits(c.area, 'NON_SCIENCE') AS non_science
                  FROM jupeb.combination c
                  JOIN jupeb.subject s1 ON s1.id = c.subject1 JOIN jupeb.subject s2 ON s2.id = c.subject2 JOIN jupeb.subject s3 ON s3.id = c.subject3
                 WHERE (c.active AND s1.active AND s2.active AND s3.active) OR NOT :active
                 ORDER BY c.code
                """).param("active", activeOnly).query().listOfRows();
    }
}
