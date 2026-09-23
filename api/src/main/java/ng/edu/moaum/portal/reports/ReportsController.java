package ng.edu.moaum.portal.reports;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The University's statutory returns, read straight off the register: enrolment
 * by faculty, programme and level, and revenue by category. Read-only — a return
 * is a view of the record, verified against it, never a change to it. The
 * admissions return is drawn from the admissions cycle it already answers with.
 */
@RestController
@RequestMapping("/api/v1/reports")
class ReportsController {

    private static final String ENROLMENT_READERS =
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')";
    private static final String REVENUE_READERS =
            "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";

    /** the School of Postgraduate Studies' own return is read by the School and the Registry */
    private static final String PG_READERS =
            "hasAnyAuthority('OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')";

    /** the accreditation return is the Registry's and HR's, read by management */
    private static final String STAFF_RATIO_READERS =
            "hasAnyAuthority('OFFICE_hrm','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    ReportsController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /* ── a Dean or Head of Department reads the same returns, scoped to their faculty or department ── */

    /** the rows that fall within the acting office's scope: by department or programme name for a
     *  department office, by faculty name for a faculty office; every row for anyone else */
    private List<Map<String, Object>> inScope(List<Map<String, Object>> rows, OfficeScope.ReportScope sc) {
        if (sc == null) return rows;
        return rows.stream().filter(r -> {
            if (sc.departmentName() != null) {
                if (r.containsKey("department")) return sc.departmentName().equals(r.get("department"));
                if (r.containsKey("programme")) return sc.programmeNames().contains(String.valueOf(r.get("programme")));
            }
            return sc.facultyName().equals(r.get("faculty"));
        }).toList();
    }

    /** the totals of a scoped row set: every numeric key summed */
    private static Map<String, Object> sums(List<Map<String, Object>> rows, String... keys) {
        Map<String, Object> t = new LinkedHashMap<>();
        for (String k : keys) t.put(k, rows.stream().mapToLong(r -> r.get(k) instanceof Number n ? n.longValue() : 0L).sum());
        return t;
    }

    /** the response with the scope it was read at, so the return can say "Faculty of Science" */
    private static Map<String, Object> withScope(Map<String, Object> out, OfficeScope.ReportScope sc) {
        Map<String, Object> m = new LinkedHashMap<>(out);
        m.put("scope", sc == null ? null : Map.of("label", sc.label(), "faculty", sc.facultyName(),
                "department", sc.departmentName() == null ? "" : sc.departmentName()));
        return m;
    }

    /** Enrolment for a session's cohort: students admitted that session, by faculty, programme and level, split by sex. */
    @GetMapping("/enrolment")
    @PreAuthorize(ENROLMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> enrolment(@RequestParam String session) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT f.name AS faculty, p.name AS programme, s.current_level AS level,
                       count(*) FILTER (WHERE s.sex = 'M') AS male,
                       count(*) FILTER (WHERE s.sex = 'F') AS female,
                       count(*) FILTER (WHERE s.sex IS NULL) AS unstated,
                       count(*) AS total
                  FROM people.student s
                  JOIN ref.programme p ON p.code = s.programme_code
                  JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE s.entry_session = :s
                   AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED')
                 GROUP BY f.name, p.name, s.current_level
                 ORDER BY f.name, p.name, s.current_level
                """).param("s", session).query().listOfRows();
        OfficeScope.ReportScope sc = scope.reportScope();
        if (sc != null) {
            rows = inScope(rows, sc);
            return withScope(Map.of("session", session, "rows", rows, "totals", sums(rows, "male", "female", "unstated", "total")), sc);
        }
        Map<String, Object> totals = jdbc.sql("""
                SELECT count(*) FILTER (WHERE s.sex = 'M') AS male,
                       count(*) FILTER (WHERE s.sex = 'F') AS female,
                       count(*) FILTER (WHERE s.sex IS NULL) AS unstated,
                       count(*) AS total
                  FROM people.student s
                 WHERE s.entry_session = :s
                   AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED')
                """).param("s", session).query().singleRow();
        return withScope(Map.of("session", session, "rows", rows, "totals", totals), null);
    }

    /** Registration cause: the not-registered students per faculty/programme split into fee-blocked
     *  (the Bursary has not cleared them) vs cleared-but-idle (cleared, not registered). Guides whether
     *  the fix is a payment plan or a reminder/window extension. See registration.registration_cause (V143). */
    @GetMapping("/registration-cause")
    @PreAuthorize(ENROLMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> registrationCause(@RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT faculty, programme, expected, registered, not_registered, fee_blocked, cleared_idle
                  FROM registration.registration_cause(:s, :sem)
                """).param("s", session).param("sem", semester).query().listOfRows();
        OfficeScope.ReportScope sc = scope.reportScope();
        rows = inScope(rows, sc);
        long exp = 0, reg = 0, nr = 0, fb = 0, ci = 0;
        for (Map<String, Object> r : rows) {
            exp += ((Number) r.get("expected")).longValue();
            reg += ((Number) r.get("registered")).longValue();
            nr += ((Number) r.get("not_registered")).longValue();
            fb += ((Number) r.get("fee_blocked")).longValue();
            ci += ((Number) r.get("cleared_idle")).longValue();
        }
        boolean inForce = Boolean.TRUE.equals(jdbc.sql("SELECT policy.in_force('clearance', 'UNIVERSITY', current_date) IS NOT NULL").query(Boolean.class).single());
        Map<String, Object> totals = new java.util.LinkedHashMap<>();
        totals.put("expected", exp); totals.put("registered", reg); totals.put("not_registered", nr);
        totals.put("fee_blocked", fb); totals.put("cleared_idle", ci);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", session); out.put("semester", semester); out.put("rows", rows);
        out.put("totals", totals); out.put("schemeInForce", inForce);
        return withScope(out, sc);
    }

    /** Outstanding carryovers, as at now: for every active student, a course whose LATEST published attempt is
     *  an F is still carried; grouped by faculty, programme and course so the office sees the re-sit load. Set-based
     *  (one pass over published sheets), not per-student. */
    @GetMapping("/carryovers")
    @PreAuthorize(ENROLMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> carryovers(@RequestParam String session) {
        String cte = """
                WITH attempts AS (
                    SELECT r.student_id, c.code AS course, c.title, e.units, r.session AS ses, r.semester AS sem, ls.points,
                           p.name AS programme, f.name AS faculty
                      FROM registration.course_registration r
                      JOIN registration.entry e ON e.registration_id = r.id AND e.status IN ('REGISTERED','APPROVED')
                      JOIN catalogue.offering o ON o.id = e.offering_id
                      JOIN catalogue.course c ON c.code = o.course_code
                      JOIN LATERAL assessment.course_final(r.student_id, o.id) ls ON ls.stage = 'PUBLISHED'
                      JOIN people.student s ON s.id = r.student_id AND s.status IN ('ACTIVE','PROBATION')
                      JOIN ref.programme p ON p.code = s.programme_code
                      JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE r.status IN ('APPROVED','LOCKED') AND ls.outcome = 'GRADED'
                ),
                latest AS (
                    SELECT DISTINCT ON (student_id, course) student_id, course, title, units, points, programme, faculty
                      FROM attempts ORDER BY student_id, course, ses DESC, sem DESC
                )
                """;
        OfficeScope.ReportScope sc = scope.reportScope();
        String scopeWhere = sc == null ? "" : sc.departmentName() != null ? " AND programme = ANY(:progs::text[])" : " AND faculty = :fac";
        var rowsQ = jdbc.sql(cte + """
                SELECT faculty, programme, course, title, max(units) AS units, count(*) AS students
                  FROM latest WHERE points = 0""" + scopeWhere + """

                 GROUP BY faculty, programme, course, title
                 ORDER BY faculty, programme, course
                """);
        var tallyQ = jdbc.sql(cte + """
                SELECT count(*) AS carried, count(DISTINCT student_id) AS students
                  FROM latest WHERE points = 0""" + scopeWhere);
        if (sc != null && sc.departmentName() != null) {
            // a Postgres array literal, each name quoted (a programme name may carry a comma)
            String progs = sc.programmeNames().stream()
                    .map(n -> "\"" + n.replace("\\", "\\\\").replace("\"", "\\\"") + "\"")
                    .collect(java.util.stream.Collectors.joining(",", "{", "}"));
            rowsQ = rowsQ.param("progs", progs); tallyQ = tallyQ.param("progs", progs);
        } else if (sc != null) {
            rowsQ = rowsQ.param("fac", sc.facultyName()); tallyQ = tallyQ.param("fac", sc.facultyName());
        }
        List<Map<String, Object>> rows = rowsQ.query().listOfRows();
        Map<String, Object> tally = tallyQ.query().singleRow();
        Map<String, Object> totals = Map.of("students", tally.getOrDefault("carried", 0L), "units", "");
        return withScope(Map.of("session", session, "rows", rows, "totals", totals,
                "distinctStudents", tally.getOrDefault("students", 0L)), sc);
    }

    /** Revenue confirmed for a session: student fees and applicant fees, by category. */
    @GetMapping("/revenue")
    @PreAuthorize(REVENUE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> revenue(@RequestParam String session) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT t.category, count(*) AS payments, coalesce(sum(t.amount), 0) AS amount
                  FROM (
                        SELECT r.purpose AS category, r.amount
                          FROM finance.payment_reference r
                         WHERE r.session = :s AND r.confirmed_at IS NOT NULL
                        UNION ALL
                        SELECT CASE fr.kind
                                   WHEN 'APPLICATION' THEN 'Application & Post-UTME'
                                   WHEN 'ACCEPTANCE'  THEN 'Acceptance'
                                   ELSE fr.kind END AS category,
                               fr.amount
                          FROM admissions.fee_reference fr
                          JOIN admissions.application a ON a.id = fr.application_id
                         WHERE a.session = :s AND fr.confirmed_at IS NOT NULL
                       ) t
                 GROUP BY t.category
                 ORDER BY amount DESC, t.category
                """).param("s", session).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT count(*) AS payments, coalesce(sum(t.amount), 0) AS amount
                  FROM (
                        SELECT r.amount FROM finance.payment_reference r
                         WHERE r.session = :s AND r.confirmed_at IS NOT NULL
                        UNION ALL
                        SELECT fr.amount FROM admissions.fee_reference fr
                          JOIN admissions.application a ON a.id = fr.application_id
                         WHERE a.session = :s AND fr.confirmed_at IS NOT NULL
                       ) t
                """).param("s", session).query().singleRow();
        return Map.of("session", session, "rows", rows, "totals", totals);
    }

    /** Expenditure for a financial year: budget, committed, spent and available by cost centre (V045). */
    @GetMapping("/expenditure")
    @PreAuthorize(REVENUE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> expenditure(@RequestParam(required = false) Integer year) {
        int y = year != null ? year : java.time.LocalDate.now().getYear();
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM expenditure.budget_performance(:y) ORDER BY cost_centre")
                .param("y", y).query().listOfRows();
        Map<String, Object> totals = jdbc.sql("""
                SELECT coalesce(sum(budget), 0) AS budget, coalesce(sum(committed), 0) AS committed,
                       coalesce(sum(spent), 0) AS spent, coalesce(sum(available), 0) AS available
                  FROM expenditure.budget_performance(:y)
                """).param("y", y).query().singleRow();
        return Map.of("year", y, "rows", rows, "totals", totals);
    }

    /**
     * The income and expenditure statement for a financial year, read off the general ledger (V145):
     * every income and expense account with its movement, the totals and the surplus or deficit, beside
     * the year's expenditure budget and what has been spent against it (V045).
     */
    @GetMapping("/income-expenditure")
    @PreAuthorize(REVENUE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> incomeExpenditure(@RequestParam(required = false) Integer year) {
        int y = year != null ? year : java.time.LocalDate.now().getYear();
        java.time.LocalDate from = java.time.LocalDate.of(y, 1, 1);
        java.time.LocalDate to = java.time.LocalDate.of(y, 12, 31);
        List<Map<String, Object>> lines = jdbc.sql("SELECT * FROM finance.income_expenditure(:f, :t)")
                .param("f", from).param("t", to).query().listOfRows();
        java.math.BigDecimal income = java.math.BigDecimal.ZERO, expense = java.math.BigDecimal.ZERO;
        for (Map<String, Object> l : lines) {
            java.math.BigDecimal amt = l.get("amount") == null ? java.math.BigDecimal.ZERO : new java.math.BigDecimal(String.valueOf(l.get("amount")));
            if ("INCOME".equalsIgnoreCase(String.valueOf(l.get("section")))) income = income.add(amt); else expense = expense.add(amt);
        }
        Map<String, Object> budget = jdbc.sql("""
                SELECT coalesce(sum(budget), 0) AS budget, coalesce(sum(committed), 0) AS committed,
                       coalesce(sum(spent), 0) AS spent, coalesce(sum(available), 0) AS available
                  FROM expenditure.budget_performance(:y)
                """).param("y", y).query().singleRow();
        Map<String, Object> totals = new java.util.LinkedHashMap<>();
        totals.put("income", income);
        totals.put("expense", expense);
        totals.put("surplus", income.subtract(expense));
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("year", y);
        out.put("from", from);
        out.put("to", to);
        out.put("lines", lines);
        out.put("totals", totals);
        out.put("budget", budget);
        return out;
    }

    /**
     * The postgraduate return for a session (V202, V211, V209): by programme, the applications the
     * session drew and how far they went (offered, accepted, admitted), the candidates on the register
     * by mode of study, and the research candidates and the awards. The register columns count every
     * postgraduate on the books, whatever session they entered; the application columns are the
     * session's own.
     */
    @GetMapping("/postgraduate")
    @PreAuthorize(PG_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> postgraduate(@RequestParam(required = false) String session) {
        String s = session == null || session.isBlank()
                ? jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).single()
                : session.trim();
        String sql = """
                WITH prog AS (
                    SELECT p.code, p.name AS programme, f.name AS faculty, admissions.pg_award_level(p.pg_award) AS pg_level
                      FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                     WHERE p.category = 'POST GRADUATE'
                ),
                app AS (
                    SELECT programme_code,
                           count(*) FILTER (WHERE state <> 'DRAFT') AS applications,
                           count(*) FILTER (WHERE state IN ('OFFERED','ACCEPTED','ADMITTED')) AS offered,
                           count(*) FILTER (WHERE state IN ('ACCEPTED','ADMITTED')) AS accepted,
                           count(*) FILTER (WHERE state = 'ADMITTED') AS admitted
                      FROM admissions.pg_application WHERE session = :s GROUP BY programme_code
                ),
                reg AS (
                    SELECT st.programme_code,
                           count(*) AS on_register,
                           count(*) FILTER (WHERE st.sex = 'F') AS female,
                           count(*) FILTER (WHERE st.sex = 'M') AS male,
                           count(*) FILTER (WHERE r.mode = 'PART_TIME') AS part_time,
                           count(*) FILTER (WHERE r.mode = 'FULL_TIME') AS full_time,
                           count(*) FILTER (WHERE rs.stage IS NOT NULL AND rs.stage NOT IN ('AWARDED','WITHDRAWN')) AS researching,
                           count(*) FILTER (WHERE rs.stage = 'AWARDED') AS awarded
                      FROM people.student st
                      LEFT JOIN LATERAL (
                            SELECT mode FROM admissions.pg_registration r WHERE r.student_id = st.id AND r.session = :s
                             ORDER BY r.semester DESC LIMIT 1) r ON true
                      LEFT JOIN admissions.pg_research rs ON rs.student_id = st.id
                     WHERE st.entry_mode = 'POSTGRADUATE'
                       AND st.status IN ('ADMITTED','ACTIVE','PROBATION','DORMANT','GRADUATED')
                     GROUP BY st.programme_code
                )
                SELECT prog.faculty, prog.code AS programme_code, prog.programme,
                       CASE prog.pg_level WHEN 900 THEN 'MPhil / PhD' WHEN 800 THEN 'Master''s' ELSE 'PGD' END AS award,
                       coalesce(app.applications, 0) AS applications, coalesce(app.offered, 0) AS offered,
                       coalesce(app.accepted, 0) AS accepted, coalesce(app.admitted, 0) AS admitted,
                       coalesce(reg.on_register, 0) AS on_register, coalesce(reg.female, 0) AS female, coalesce(reg.male, 0) AS male,
                       coalesce(reg.full_time, 0) AS full_time, coalesce(reg.part_time, 0) AS part_time,
                       coalesce(reg.researching, 0) AS researching, coalesce(reg.awarded, 0) AS awarded
                  FROM prog LEFT JOIN app ON app.programme_code = prog.code
                            LEFT JOIN reg ON reg.programme_code = prog.code
                 WHERE coalesce(app.applications, 0) + coalesce(reg.on_register, 0) > 0
                 ORDER BY prog.faculty, prog.programme
                """;
        OfficeScope.ReportScope sc = scope.reportScope();
        List<Map<String, Object>> rows = inScope(jdbc.sql(sql).param("s", s).query().listOfRows(), sc);
        Map<String, Object> totals = new LinkedHashMap<>();
        for (String k : List.of("applications", "offered", "accepted", "admitted", "on_register", "female", "male", "full_time", "part_time", "researching", "awarded")) {
            totals.put(k, rows.stream().mapToLong(r -> ((Number) r.get(k)).longValue()).sum());
        }
        return withScope(Map.of("session", s, "rows", rows, "totals", totals), sc);
    }

    /**
     * Staff/student ratio by department, for the NUC accreditation return: the students on the
     * books under each department's programmes against the academic staff whose home department it
     * is (V137 staff record, holding the lecturer office), with the rank mix that the qualification
     * table of the return is built from. The ratio is students per academic staff.
     */
    @GetMapping("/staff-ratio")
    @PreAuthorize(STAFF_RATIO_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> staffRatio() {
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH staff AS (
                    SELECT r.home_department AS dept,
                           count(*) AS academic,
                           count(*) FILTER (WHERE upper(coalesce(r.present_rank, '')) LIKE '%PROFESSOR%' OR upper(coalesce(r.present_rank, '')) LIKE '%READER%') AS professorial,
                           count(*) FILTER (WHERE upper(coalesce(r.present_rank, '')) LIKE 'SENIOR LECTURER%') AS senior,
                           count(*) FILTER (WHERE upper(coalesce(r.present_rank, '')) LIKE 'LECTURER%') AS lecturers,
                           count(*) FILTER (WHERE upper(coalesce(r.present_rank, '')) LIKE 'ASSISTANT%' OR upper(coalesce(r.present_rank, '')) LIKE 'GRADUATE%') AS junior
                      FROM hrm.staff_record r
                     WHERE r.home_department IS NOT NULL
                       AND EXISTS (SELECT 1 FROM iam.office_assignment a
                                    WHERE a.person_id = r.person_id AND a.office_code IN ('lecturer','hod','dean')
                                      AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))
                     GROUP BY r.home_department
                ),
                students AS (
                    SELECT p.dept_code AS dept, count(*) AS students,
                           count(*) FILTER (WHERE s.entry_mode = 'POSTGRADUATE') AS postgraduates
                      FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                     WHERE s.status IN ('ADMITTED','ACTIVE','PROBATION')
                     GROUP BY p.dept_code
                )
                SELECT f.name AS faculty, d.code AS department_code, d.name AS department,
                       coalesce(st.students, 0) AS students, coalesce(st.postgraduates, 0) AS postgraduates,
                       coalesce(sf.academic, 0) AS academic,
                       coalesce(sf.professorial, 0) AS professorial, coalesce(sf.senior, 0) AS senior,
                       coalesce(sf.lecturers, 0) AS lecturers, coalesce(sf.junior, 0) AS junior,
                       CASE WHEN coalesce(sf.academic, 0) > 0 THEN round(coalesce(st.students, 0)::numeric / sf.academic, 1) END AS ratio
                  FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code
                  LEFT JOIN staff sf ON sf.dept = d.code
                  LEFT JOIN students st ON st.dept = d.code
                 WHERE d.ended_on IS NULL AND (coalesce(st.students, 0) + coalesce(sf.academic, 0)) > 0
                 ORDER BY f.name, d.name
                """).query().listOfRows();
        OfficeScope.ReportScope sc = scope.reportScope();
        rows = inScope(rows, sc);
        Map<String, Object> totals = new LinkedHashMap<>();
        for (String k : List.of("students", "postgraduates", "academic", "professorial", "senior", "lecturers", "junior")) {
            totals.put(k, rows.stream().mapToLong(r -> ((Number) r.get(k)).longValue()).sum());
        }
        long students = (Long) totals.get("students"), academic = (Long) totals.get("academic");
        totals.put("ratio", academic > 0 ? Math.round((10.0 * students) / academic) / 10.0 : null);
        return withScope(Map.of("rows", rows, "totals", totals), sc);
    }

    /**
     * Period over period, for the returns desk: the last three sessions side by side (students
     * admitted, applications and offers, postgraduate applications, carryovers) and the last six
     * months (fees confirmed, vouchers paid). Read off the same tables the returns are, so a
     * figure here is the figure the return will print.
     */
    @GetMapping("/trends")
    @PreAuthorize(ENROLMENT_READERS + " or " + REVENUE_READERS + " or " + PG_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> trends() {
        List<Map<String, Object>> sessions = jdbc.sql("""
                WITH names AS (
                    SELECT name FROM policy.academic_session
                    UNION SELECT entry_session FROM people.student
                    UNION SELECT session FROM admissions.candidate
                ),
                last3 AS (SELECT name FROM names WHERE name ~ '^[0-9]{4}/[0-9]{4}$' ORDER BY name DESC LIMIT 3)
                SELECT n.name AS session,
                       (SELECT count(*) FROM people.student s WHERE s.entry_session = n.name) AS admitted,
                       (SELECT count(*) FROM people.student s WHERE s.entry_session = n.name AND s.sex = 'F') AS female,
                       (SELECT count(*) FROM people.student s WHERE s.entry_session = n.name AND s.sex = 'M') AS male,
                       (SELECT count(*) FROM people.student s WHERE s.entry_session = n.name AND s.entry_mode = 'POSTGRADUATE') AS postgraduate,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = n.name) AS candidates,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = n.name AND c.offer_state IN ('ADMITTED','ACCEPTED')) AS offered,
                       (SELECT count(*) FROM admissions.candidate c WHERE c.session = n.name AND c.offer_state = 'ACCEPTED') AS accepted,
                       (SELECT count(*) FROM admissions.pg_application a WHERE a.session = n.name AND a.state <> 'DRAFT') AS pg_applications,
                       (SELECT count(*) FROM admissions.pg_application a WHERE a.session = n.name AND a.state IN ('OFFERED','ACCEPTED','ADMITTED')) AS pg_offered,
                       (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r WHERE r.session = n.name AND r.confirmed_at IS NOT NULL) AS fees_confirmed
                  FROM last3 n ORDER BY n.name
                """).query().listOfRows();
        List<Map<String, Object>> months = jdbc.sql("""
                WITH m AS (
                    SELECT (date_trunc('month', current_date) - (g || ' month')::interval)::date AS month
                      FROM generate_series(5, 0, -1) g
                )
                SELECT to_char(m.month, 'YYYY-MM') AS month, to_char(m.month, 'Mon YYYY') AS label,
                       (SELECT coalesce(sum(r.amount), 0) FROM finance.payment_reference r
                         WHERE r.confirmed_at >= m.month AND r.confirmed_at < m.month + interval '1 month') AS fees,
                       (SELECT count(*) FROM finance.payment_reference r
                         WHERE r.confirmed_at >= m.month AND r.confirmed_at < m.month + interval '1 month') AS payments,
                       (SELECT coalesce(sum(v.amount), 0) FROM expenditure.voucher v
                         WHERE v.paid_at >= m.month AND v.paid_at < m.month + interval '1 month') AS paid,
                       (SELECT coalesce(sum(v.amount), 0) FROM expenditure.voucher v
                         WHERE v.raised_at >= m.month AND v.raised_at < m.month + interval '1 month' AND v.stage <> 'REJECTED') AS raised
                  FROM m ORDER BY m.month
                """).query().listOfRows();
        return Map.of("sessions", sessions, "months", months);
    }
}
