package ng.edu.moaum.portal.hrm;

import java.util.LinkedHashMap;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Director of Human Resource Management's home: the establishment at a glance and what is waiting on
 * the directorate — leave to decide, movements approved but not yet issued, vacancies open, and the pay
 * run in hand. Read-only; each figure is the HR module's own (V071–V076).
 */
@RestController
class HrController {

    private final JdbcClient jdbc;

    HrController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/api/v1/hr/dashboard")
    @PreAuthorize("hasAnyAuthority('OFFICE_hrm','OFFICE_super')")
    @Transactional(readOnly = true)
    Map<String, Object> dashboard() {
        Map<String, Object> out = new LinkedHashMap<>();
        String cycle = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'")
                .query(String.class).optional().orElse("2026/2027");
        out.put("cycle", cycle);

        out.put("staffActive", jdbc.sql("SELECT count(*) FROM hrm.employment WHERE status = 'ACTIVE'").query(Long.class).single());
        out.put("leavePending", jdbc.sql("SELECT count(*) FROM hrm.leave_list('REQUESTED')").query(Long.class).single());
        out.put("onLeaveToday", jdbc.sql("""
                SELECT count(*) FROM hrm.leave_list('APPROVED')
                 WHERE from_date <= current_date AND to_date >= current_date
                """).query(Long.class).single());
        out.put("movementsAwaiting", jdbc.sql("SELECT count(*) FROM hrm.movement_list('APPROVED')").query(Long.class).single());
        out.put("vacanciesOpen", jdbc.sql("SELECT count(*) FROM hrm.vacancy WHERE state = 'OPEN'").query(Long.class).single());
        out.put("shortlisted", jdbc.sql("SELECT count(*) FROM hrm.applicant WHERE state = 'SHORTLISTED'").query(Long.class).single());
        out.put("payDraft", jdbc.sql("SELECT count(*) FROM hrm.pay_run WHERE state = 'DRAFT'").query(Long.class).single());
        out.put("appraisals", jdbc.sql("SELECT count(*) FROM hrm.appraisal WHERE cycle = :c").param("c", cycle).query(Long.class).single());
        out.put("latestRun", jdbc.sql("SELECT period, state, staff_count, net_total FROM hrm.pay_run ORDER BY period DESC LIMIT 1")
                .query().listOfRows().stream().findFirst().orElse(null));

        out.put("leave", jdbc.sql("""
                SELECT name, staff_no, type_name, days, from_date
                  FROM hrm.leave_list('REQUESTED') ORDER BY requested_at LIMIT 10
                """).query().listOfRows());
        out.put("movements", jdbc.sql("""
                SELECT name, staff_no, what_changes, effective_date
                  FROM hrm.movement_list('APPROVED') ORDER BY effective_date LIMIT 10
                """).query().listOfRows());
        return out;
    }
}
