package ng.edu.moaum.portal.finance;

import java.sql.Types;
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
 * The school fees report (Oct 2026): for a session, every faculty, department and level — the students who have paid in full, the
 * students still owing (part payments among them), what was paid and what is still owed — with the grand total. Each student's
 * position is finance.session_positions, the one the College payment report, Student Accounts and the fees page read: due by the fee
 * setup for the student's programme and level on the record, paid from the session's confirmed school-fees payments (portal, gateway,
 * old portal, carried), short by under ₦1 counted as paid (V454). The students counted are those on the register (active or on
 * probation), the session's new intake not yet matriculated, and anyone else who paid school fees in the session. A Dean or Faculty
 * Officer reads their faculty, a Head of Department their department.
 */
@RestController
@RequestMapping("/api/v1/finance")
class FeeReportController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_academic','OFFICE_vc','OFFICE_dvc','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod',"
            // 22 Oct 2026: the College Finance Controller, held to the College by OfficeScope.bound as a Dean to a faculty
            + "'OFFICE_financecontroller')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final tools.jackson.databind.ObjectMapper json;

    FeeReportController(JdbcClient jdbc, OfficeScope scope, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.json = json;
    }

    @GetMapping("/fee-report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> report(@RequestParam(required = false) String session, @RequestParam(required = false) String fac,
                               @RequestParam(required = false) String dept) {
        String ses = session != null && session.matches("^[0-9]{4}/[0-9]{4}$") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        OfficeScope.Bound b = scope.bound(fac, dept, null);
        // planned with the session as a value, not a constant: on the live-shaped copy the plan made for a constant session took
        // 12–34 s (finance.session_positions planned into the whole), the plan for a value 0.7–1.5 s; the driver plans a statement's
        // first runs for their constants, so the choice is made here, for this transaction only
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_generic_plan', true)").query().singleRow();
        String text = jdbc.sql("""
                WITH pos AS MATERIALIZED (SELECT * FROM finance.session_positions(:s, NULL)),
                -- V637: who is charged the spillover lines (SP1/SP2 at the final level, or above it), so spillover fees are shown apart
                sp AS MATERIALIZED (SELECT x.student_id, x.is_spill FROM finance.fee_profiles(:s) x WHERE x.is_spill),
                st AS MATERIALIZED (
                    SELECT s.id, p.faculty_code, f.name AS faculty, p.dept_code, d.name AS department, s.current_level AS level, s.status, s.entry_session
                      FROM people.student s
                      JOIN ref.programme p ON p.code = s.programme_code
                      JOIN ref.faculty f ON f.code = p.faculty_code
                      JOIN ref.department d ON d.code = p.dept_code
                     WHERE (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept)),
                -- on the register, the session's new intake, and anyone who paid school fees in the session
                j AS MATERIALIZED (
                    SELECT st.*, pos.payable, pos.paid, pos.outstanding, pos.status AS fee_status, (sp.student_id IS NOT NULL) AS is_spill
                      FROM st JOIN pos ON pos.student_id = st.id
                      LEFT JOIN sp ON sp.student_id = st.id
                     WHERE st.status IN ('ACTIVE', 'PROBATION') OR (st.status = 'ADMITTED' AND st.entry_session = :s) OR pos.paid > 0),
                g AS (
                    SELECT j.faculty_code, j.faculty, j.dept_code, j.department, j.level,
                           count(*) AS students,
                           count(*) FILTER (WHERE j.fee_status = 'FULLY_PAID' OR (j.fee_status = 'NO_CHARGE' AND j.paid > 0)) AS paid_students,
                           count(*) FILTER (WHERE j.fee_status IN ('PART_PAYMENT', 'NOT_PAID')) AS owing_students,
                           count(*) FILTER (WHERE j.fee_status = 'PART_PAYMENT') AS part_paid,
                           count(*) FILTER (WHERE j.fee_status = 'NO_CHARGE' AND j.paid = 0) AS no_fee,
                           coalesce(sum(j.payable), 0) AS amount_due, coalesce(sum(j.paid), 0) AS amount_paid, coalesce(sum(j.outstanding), 0) AS amount_owing,
                           count(*) FILTER (WHERE j.is_spill) AS spill_students,
                           coalesce(sum(j.payable) FILTER (WHERE j.is_spill), 0) AS spill_due, coalesce(sum(j.paid) FILTER (WHERE j.is_spill), 0) AS spill_paid,
                           coalesce(sum(j.outstanding) FILTER (WHERE j.is_spill), 0) AS spill_owing
                      FROM j GROUP BY j.faculty_code, j.faculty, j.dept_code, j.department, j.level)
                SELECT json_build_object(
                    'session', :s::text,
                    'sessions', (SELECT coalesce(json_agg(a.name ORDER BY a.starts_on DESC), '[]'::json) FROM policy.academic_session a
                                  WHERE a.state NOT IN ('DRAFT', 'CANCELLED') AND a.name ~ '^[0-9]{4}/[0-9]{4}$'),
                    'faculty', :fac::text, 'department', :dept::text,
                    'rows', (SELECT coalesce(json_agg(g ORDER BY g.faculty, g.department, g.level NULLS LAST), '[]'::json) FROM g),
                    'total', (SELECT json_build_object('students', coalesce(sum(students), 0), 'paid_students', coalesce(sum(paid_students), 0),
                                                       'owing_students', coalesce(sum(owing_students), 0), 'part_paid', coalesce(sum(part_paid), 0),
                                                       'no_fee', coalesce(sum(no_fee), 0), 'amount_due', coalesce(sum(amount_due), 0),
                                                       'amount_paid', coalesce(sum(amount_paid), 0), 'amount_owing', coalesce(sum(amount_owing), 0),
                                                       'spill_students', coalesce(sum(spill_students), 0), 'spill_due', coalesce(sum(spill_due), 0),
                                                       'spill_paid', coalesce(sum(spill_paid), 0), 'spill_owing', coalesce(sum(spill_owing), 0)) FROM g),
                    'generatedAt', now()
                )::text
                """).param("s", ses).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).query(String.class).single();
        return json.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }

    /** the faculties and departments the reader may choose from, within their scope */
    @GetMapping("/fee-report/structure")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> structure() {
        OfficeScope.Bound b = scope.bound(null, null, null);
        return jdbc.sql("""
                SELECT f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department
                  FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE (:fac::text IS NULL OR f.code = :fac) AND (:dept::text IS NULL OR d.code = :dept)
                 ORDER BY f.name, d.name
                """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).query().listOfRows();
    }
}
