package ng.edu.moaum.portal.reports;

import java.util.List;
import java.util.Map;

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
            "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final String REVENUE_READERS =
            "hasAnyAuthority('OFFICE_bursar','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";

    private final JdbcClient jdbc;

    ReportsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
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
        Map<String, Object> totals = jdbc.sql("""
                SELECT count(*) FILTER (WHERE s.sex = 'M') AS male,
                       count(*) FILTER (WHERE s.sex = 'F') AS female,
                       count(*) FILTER (WHERE s.sex IS NULL) AS unstated,
                       count(*) AS total
                  FROM people.student s
                 WHERE s.entry_session = :s
                   AND s.status NOT IN ('WITHDRAWN','EXPELLED','TRANSFERRED_OUT','DECEASED')
                """).param("s", session).query().singleRow();
        return Map.of("session", session, "rows", rows, "totals", totals);
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
        return out;
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
        List<Map<String, Object>> rows = jdbc.sql(cte + """
                SELECT faculty, programme, course, title, max(units) AS units, count(*) AS students
                  FROM latest WHERE points = 0
                 GROUP BY faculty, programme, course, title
                 ORDER BY faculty, programme, course
                """).query().listOfRows();
        Map<String, Object> tally = jdbc.sql(cte + """
                SELECT count(*) AS carried, count(DISTINCT student_id) AS students
                  FROM latest WHERE points = 0
                """).query().singleRow();
        Map<String, Object> totals = Map.of("students", tally.getOrDefault("carried", 0L), "units", "");
        return Map.of("session", session, "rows", rows, "totals", totals,
                "distinctStudents", tally.getOrDefault("students", 0L));
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
}
