package ng.edu.moaum.portal.analytics;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.stats.AnalyticsScope;
import ng.edu.moaum.portal.stats.AnalyticsScope.Bound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The admission funnel (V279): a session's applications counted at every stage of the
 * lifecycle the portal already records — applied, application fee paid, admitted,
 * checking fee paid, accepted, screening submitted, screening successful, on the
 * register, school fees paid, courses registered, matriculated — within the acting
 * office's scope, and the applicants behind any stage a page at a time. The
 * Postgraduate School reads its own funnel from the School's applications.
 */
@RestController
@RequestMapping("/api/v1/analytics/admissions")
class AdmissionFunnelController {

    private static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_academic','OFFICE_records',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_dvc','OFFICE_vc','OFFICE_pgschool','OFFICE_pgsecretary',"
            + "'OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_audit')";

    /** the undergraduate stages, in the order the lifecycle walks them */
    static final List<String[]> UG = List.of(
            new String[] { "applied", "Applications" }, new String[] { "fee_paid", "Application fee paid" }, new String[] { "admitted", "Admitted" },
            new String[] { "checking_paid", "Checking fee paid" }, new String[] { "accepted", "Acceptance paid" }, new String[] { "screening_submitted", "Screening submitted" },
            new String[] { "screening_ok", "Screening successful" }, new String[] { "on_register", "On the register" }, new String[] { "fees_paid", "School fees paid" },
            new String[] { "registered", "Courses registered" }, new String[] { "matriculated", "Matriculated" });
    /** the postgraduate stages */
    static final List<String[]> PG = List.of(
            new String[] { "applied", "Applications" }, new String[] { "fee_paid", "Application fee paid" }, new String[] { "submitted", "Submitted" },
            new String[] { "dept_decided", "Department decided" }, new String[] { "admitted", "Offered" }, new String[] { "checking_paid", "Checking fee paid" },
            new String[] { "accepted", "Acceptance paid" }, new String[] { "on_register", "Admitted to the register" });

    private final JdbcClient jdbc;
    private final AnalyticsScope scope;

    AdmissionFunnelController(JdbcClient jdbc, AnalyticsScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static final String UG_ROWS = """
            SELECT ap.id, ap.session, ap.application_no, c.surname, c.other_names, c.jamb_reg_no, c.programme, c.entry_mode, coalesce(s.sex, cr.sex) AS sex,
                   p.code AS programme_code, f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department,
                   (coalesce(f.college_code, '') = 'CHS') AS is_chs, s.id AS student_id, s.admission_no, s.matric_no,
                   true AS applied,
                   ap.fee_confirmed_at IS NOT NULL AS fee_paid,
                   (ap.decision_released_at IS NOT NULL AND ap.decision = 'OFFERED') AS admitted,
                   ap.checking_confirmed_at IS NOT NULL AS checking_paid,
                   ap.accepted_at IS NOT NULL AS accepted,
                   EXISTS (SELECT 1 FROM admissions.screening_form sf WHERE sf.application_id = ap.id AND sf.state IN ('SUBMITTED','UNDER_REVIEW','SUCCESSFUL','UNSUCCESSFUL')) AS screening_submitted,
                   (ap.accepted_at IS NOT NULL AND admissions.screening_required(ap.id) AND EXISTS (SELECT 1 FROM admissions.screening_form sf WHERE sf.application_id = ap.id AND sf.state = 'SUCCESSFUL')) AS screening_ok,
                   s.id IS NOT NULL AS on_register,
                   (s.id IS NOT NULL AND (SELECT pp.status FROM finance.payment_position(s.id, ap.session, NULL) pp) = 'FULLY_PAID') AS fees_paid,
                   (s.id IS NOT NULL AND EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = s.id AND r.session = ap.session AND r.status IN ('SUBMITTED','APPROVED','LOCKED'))) AS registered,
                   s.matric_no IS NOT NULL AS matriculated,
                   ap.fee_confirmed_at, ap.decision_released_at, ap.accepted_at, ap.cleared_at
              FROM admissions.application ap
              JOIN admissions.candidate c ON c.id = ap.candidate_id
              LEFT JOIN admissions.caps_row cr ON cr.id = c.admitted_from
              LEFT JOIN people.student s ON s.candidate_id = c.id
              LEFT JOIN ref.programme p ON p.code = admissions.programme_code_of(c.programme)
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
             WHERE ap.session = :s
               AND (:chs::boolean IS NULL OR coalesce(f.college_code, '') = 'CHS')
               AND (:bf::text IS NULL OR f.code = :bf)
               AND (:bd::text IS NULL OR d.code = :bd)
               AND (:fac::text IS NULL OR f.code = :fac)
               AND (:dept::text IS NULL OR d.code = :dept)
               AND (:prog::text IS NULL OR p.code = :prog)
               AND (:sex::text IS NULL OR coalesce(s.sex, cr.sex) = :sex)
               AND (:entry::text IS NULL OR c.entry_mode = :entry)
               AND (:q::text IS NULL OR lower(c.surname || ' ' || c.other_names) LIKE :q OR lower(c.jamb_reg_no) LIKE :q OR lower(ap.application_no) LIKE :q)
            """;
    private static final String PG_ROWS = """
            SELECT pa.id, pa.session, pa.application_no, ap.surname, ap.other_names, NULL::text AS jamb_reg_no, p.name AS programme, 'POSTGRADUATE' AS entry_mode, ap.sex,
                   p.code AS programme_code, f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department,
                   (coalesce(f.college_code, '') = 'CHS') AS is_chs, s.id AS student_id, s.admission_no, s.matric_no,
                   true AS applied,
                   pa.fee_confirmed_at IS NOT NULL AS fee_paid,
                   pa.submitted_at IS NOT NULL AS submitted,
                   pa.dept_decided_at IS NOT NULL AS dept_decided,
                   pa.state IN ('OFFERED','ACCEPTED','ADMITTED') AS admitted,
                   pa.checking_confirmed_at IS NOT NULL AS checking_paid,
                   pa.accepted_at IS NOT NULL AS accepted,
                   pa.student_id IS NOT NULL AS on_register,
                   pa.fee_confirmed_at, pa.spgs_decided_at AS decision_released_at, pa.accepted_at, pa.admitted_at AS cleared_at
              FROM admissions.pg_application pa
              JOIN admissions.pg_applicant ap ON ap.id = pa.applicant_id
              LEFT JOIN people.student s ON s.id = pa.student_id
              LEFT JOIN ref.programme p ON p.code = pa.programme_code
              LEFT JOIN ref.faculty f ON f.code = p.faculty_code
              LEFT JOIN ref.department d ON d.code = p.dept_code
             WHERE pa.session = :s AND pa.state <> 'DRAFT'
               AND (:chs::boolean IS NULL OR coalesce(f.college_code, '') = 'CHS')
               AND (:bf::text IS NULL OR f.code = :bf)
               AND (:bd::text IS NULL OR d.code = :bd)
               AND (:fac::text IS NULL OR f.code = :fac)
               AND (:dept::text IS NULL OR d.code = :dept)
               AND (:prog::text IS NULL OR p.code = :prog)
               AND (:sex::text IS NULL OR ap.sex = :sex)
               AND (:entry::text IS NULL OR 'POSTGRADUATE' = :entry)
               AND (:q::text IS NULL OR lower(ap.surname || ' ' || ap.other_names) LIKE :q OR lower(pa.application_no) LIKE :q)
            """;

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private String session(String session) {
        if (session != null && session.matches("\\d{4}/\\d{4}")) return session;
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1").query(String.class).single());
    }

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec q, Bound b, String s, String fac, String dept, String prog, String sex, String entry, String search) {
        String sx = sex == null ? null : sex.trim().toUpperCase();
        return q.param("s", s).param("chs", b.chs() ? Boolean.TRUE : null, Types.BOOLEAN)
                .param("bf", b.faculty(), Types.VARCHAR).param("bd", b.dept(), Types.VARCHAR)
                .param("fac", blank(fac), Types.VARCHAR).param("dept", blank(dept), Types.VARCHAR).param("prog", blank(prog), Types.VARCHAR)
                .param("sex", "M".equals(sx) || "F".equals(sx) ? sx : null, Types.VARCHAR).param("entry", blank(entry) == null ? null : entry.trim().toUpperCase(), Types.VARCHAR)
                .param("q", search == null || search.isBlank() ? null : "%" + search.trim().toLowerCase() + "%", Types.VARCHAR);
    }

    /** the stages and their counts for a session, within the scope */
    @GetMapping("/funnel")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> funnel(@RequestParam(required = false) String session, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                               @RequestParam(required = false) String prog, @RequestParam(required = false) String sex, @RequestParam(required = false) String entry,
                               @RequestParam(required = false) String q) {
        Bound b = scope.bound();
        String s = session(session);
        List<String[]> stages = b.pg() ? PG : UG;
        String counts = String.join(", ", stages.stream().map(st -> "count(*) FILTER (WHERE " + st[0] + ") AS " + st[0]).toList());
        Map<String, Object> row = bind(jdbc.sql("WITH a AS (" + (b.pg() ? PG_ROWS : UG_ROWS) + ") SELECT " + counts + " FROM a"), b, s, fac, dept, prog, sex, entry, q).query().singleRow();
        List<Map<String, Object>> out = new ArrayList<>();
        for (String[] st : stages) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("key", st[0]);
            m.put("label", st[1]);
            m.put("count", ((Number) row.get(st[0])).longValue());
            out.add(m);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scope", Map.of("kind", b.kind(), "label", b.label(), "pg", b.pg()));
        res.put("session", s);
        res.put("stages", out);
        res.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        return res;
    }

    /** the applicants at a stage: the same rows, a page at a time, names A–Z */
    @GetMapping("/funnel/rows")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rows(@RequestParam(required = false) String session, @RequestParam(defaultValue = "applied") String stage,
                             @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) String sex, @RequestParam(required = false) String entry, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        Bound b = scope.bound();
        String s = session(session);
        List<String[]> stages = b.pg() ? PG : UG;
        String st = stages.stream().map(x -> x[0]).filter(x -> x.equals(stage)).findFirst().orElse("applied");
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql("WITH a AS (" + (b.pg() ? PG_ROWS : UG_ROWS) + ") SELECT count(*) OVER () AS total_rows, a.* FROM a WHERE a." + st
                + " ORDER BY a.surname, a.other_names LIMIT :n OFFSET :o"), b, s, fac, dept, prog, sex, entry, q).param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> x = new LinkedHashMap<>(r);
            x.remove("total_rows");
            x.remove("id");
            out.add(x);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scope", Map.of("kind", b.kind(), "label", b.label(), "pg", b.pg()));
        res.put("session", s);
        res.put("stage", st);
        res.put("label", stages.stream().filter(x -> x[0].equals(st)).map(x -> x[1]).findFirst().orElse(st));
        res.put("total", total);
        res.put("page", pg);
        res.put("size", sz);
        res.put("rows", out);
        return res;
    }
}
