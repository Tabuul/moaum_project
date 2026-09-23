package ng.edu.moaum.portal.hrm;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.NotFound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The payroll (V069): the establishment, the monthly runs, and a staff member's own payslips. */
@RestController
class PayrollController {

    private static final String READERS = "hasAnyAuthority('OFFICE_hrm','OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    private static final String PAYROLL = "hasAnyAuthority('OFFICE_hrm','OFFICE_super')";

    private final JdbcClient jdbc;

    PayrollController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    public record Build(@NotBlank @Pattern(regexp = "\\d{4}-\\d{2}") String period, @Size(max = 400) String note) {
    }

    public record Why(@NotBlank @Size(max = 400) String why) {
    }

    private static LocalDate firstOfMonth(String period) {
        return LocalDate.parse(period + "-01");
    }

    /* ── the establishment and the salary structure ── */

    @GetMapping("/api/v1/payroll/staff")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> establishment() {
        return jdbc.sql("""
                SELECT em.id, p.id AS person_id, em.staff_no, em.grade, em.step, em.category, em.status, em.appointment_date,
                       p.surname || ', ' || p.given_names AS name, em.bank_name, em.account_last4,
                       gr.basic + gr.housing + gr.transport + gr.other_allowances AS gross
                  FROM hrm.employment em
                  JOIN iam.person p ON p.id = em.person_id
                  LEFT JOIN hrm.grade gr ON gr.grade = em.grade AND gr.step = em.step
                 ORDER BY (em.status = 'ACTIVE') DESC, em.staff_no
                """).query().listOfRows();
    }

    @GetMapping("/api/v1/payroll/grades")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> grades() {
        return jdbc.sql("SELECT grade, step, category, basic, housing, transport, other_allowances, basic + housing + transport + other_allowances AS gross FROM hrm.grade ORDER BY category, grade, step").query().listOfRows();
    }

    /* ── the runs ── */

    @GetMapping("/api/v1/payroll/runs")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> runs() {
        return jdbc.sql("""
                SELECT r.id, r.period, r.state, r.staff_count, r.gross_total, r.deduction_total, r.net_total, r.note,
                       r.built_at, r.approved_at, r.paid_at, r.cancelled_why,
                       bp.surname || ', ' || bp.given_names AS built_by_name,
                       CASE WHEN ap.id IS NULL THEN NULL ELSE ap.surname || ', ' || ap.given_names END AS approved_by_name,
                       r.built_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS built_by_me
                  FROM hrm.pay_run r
                  LEFT JOIN iam.person bp ON bp.id = r.built_by
                  LEFT JOIN iam.person ap ON ap.id = r.approved_by
                 ORDER BY r.period DESC
                """).query().listOfRows();
    }

    @GetMapping("/api/v1/payroll/runs/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> run(@PathVariable UUID id) {
        List<Map<String, Object>> head = jdbc.sql("""
                SELECT r.id, r.period, r.state, r.staff_count, r.gross_total, r.deduction_total, r.net_total, r.note,
                       r.built_at, r.approved_at, r.paid_at, r.cancelled_why,
                       bp.surname || ', ' || bp.given_names AS built_by_name,
                       CASE WHEN ap.id IS NULL THEN NULL ELSE ap.surname || ', ' || ap.given_names END AS approved_by_name,
                       r.built_by = nullif(current_setting('moaum.actor_id', true), '')::uuid AS built_by_me
                  FROM hrm.pay_run r
                  LEFT JOIN iam.person bp ON bp.id = r.built_by
                  LEFT JOIN iam.person ap ON ap.id = r.approved_by
                 WHERE r.id = :id
                """).param("id", id).query().listOfRows();
        if (head.isEmpty()) {
            throw new NotFound("pay run", id.toString());
        }
        List<Map<String, Object>> slips = jdbc.sql("""
                SELECT staff_no, name, grade, step, category, basic, allowances, gross, pension, paye, other_deductions, net, bank_name, account_last4
                  FROM hrm.payslip WHERE run_id = :id ORDER BY staff_no
                """).param("id", id).query().listOfRows();
        return Map.of("run", head.get(0), "payslips", slips);
    }

    @PostMapping("/api/v1/payroll/runs")
    @PreAuthorize(PAYROLL)
    @Transactional
    Map<String, Object> build(@Valid @RequestBody Build body) {
        return jdbc.sql("SELECT * FROM hrm.build_pay_run(:p, :n)")
                .param("p", firstOfMonth(body.period())).param("n", body.note(), java.sql.Types.VARCHAR)
                .query().singleRow();
    }

    @PostMapping("/api/v1/payroll/runs/{id}/approve")
    @PreAuthorize(PAYROLL)
    @Transactional
    Map<String, Object> approve(@PathVariable UUID id) {
        jdbc.sql("SELECT hrm.approve_pay_run(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "APPROVED");
    }

    @PostMapping("/api/v1/payroll/runs/{id}/pay")
    @PreAuthorize(PAYROLL)
    @Transactional
    Map<String, Object> pay(@PathVariable UUID id) {
        jdbc.sql("SELECT hrm.pay_pay_run(:id)").param("id", id).query().singleRow();
        return Map.of("id", id, "state", "PAID");
    }

    @PostMapping("/api/v1/payroll/runs/{id}/cancel")
    @PreAuthorize(PAYROLL)
    @Transactional
    Map<String, Object> cancel(@PathVariable UUID id, @Valid @RequestBody Why body) {
        jdbc.sql("SELECT hrm.cancel_pay_run(:id, :w)").param("id", id).param("w", body.why()).query().singleRow();
        return Map.of("id", id, "state", "CANCELLED");
    }

    @GetMapping("/api/v1/payroll/variance")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> variance(@RequestParam String period) {
        LocalDate p = firstOfMonth(period);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM hrm.pay_run_variance(:p)").param("p", p).query().listOfRows();
        return Map.of("period", p, "rows", rows);
    }

    /* ── a staff member's own payslips ── */

    @GetMapping("/api/v1/me/payslips")
    @PreAuthorize("isAuthenticated()")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(Authentication auth) {
        UUID me = actor(auth);
        if (me == null) {
            return List.of();
        }
        return jdbc.sql("""
                SELECT s.staff_no, s.name, s.grade, s.step, s.category, s.basic, s.allowances, s.gross,
                       s.pension, s.paye, s.other_deductions, s.net, s.bank_name, s.account_last4,
                       r.period, r.state, r.paid_at
                  FROM hrm.payslip s JOIN hrm.pay_run r ON r.id = s.run_id
                 WHERE s.person_id = :me AND r.state IN ('APPROVED','PAID')
                 ORDER BY r.period DESC
                """).param("me", me).query().listOfRows();
    }

    private static UUID actor(Authentication auth) {
        return AuditContextHolder.current().map(c -> c.actorId()).orElseGet(() -> {
            if (auth == null || auth.getName() == null) {
                return null;
            }
            try {
                return UUID.fromString(auth.getName());
            } catch (IllegalArgumentException notUuid) {
                return null;
            }
        });
    }
}
