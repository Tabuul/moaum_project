package ng.edu.moaum.portal.finance;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Bursary's spillover list (V637): every student in study charged the spillover lines for a session — SP1/SP2 at the final level
 * as the level desk sets them, or above it — with the SP year, the semesters a course is registered in (a semester's spillover fee is
 * owed only then, V616), the carry-overs the published results state, due, paid, owing and where each stands. The database decides who
 * is in spillover and what is owed (finance.spillover_students); a College reader is held to the College (OfficeScope.bound).
 */
@RestController
@RequestMapping("/api/v1/finance/spillover")
class SpilloverFeesController {

    // the School Fees Report's readers (FeeReportController): a Dean, faculty officer, Head or the College Finance Controller held to their own by OfficeScope.bound
    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_academic','OFFICE_vc','OFFICE_dvc','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod',"
            + "'OFFICE_financecontroller',"
            // V640: the Database Operations office
            + "'OFFICE_dbops')";
    private static final Set<String> STATES = Set.of("NOT_REGISTERED", "NO_CHARGE", "OWES", "PART_PAID", "PAID", "PAID_ABOVE");

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    SpilloverFeesController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) String fac,
                             @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) Integer year, @RequestParam(required = false) String state,
                             @RequestParam(required = false) String q, @RequestParam(defaultValue = "1000") int limit) {
        String ses = session != null && session.matches("^[0-9]{4}/[0-9]{4}$") ? session
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).single();
        String st = blank(state);
        if (st != null && !STATES.contains(st)) {
            throw new DomainRuleViolation("SPILLOVER_STATE", "That is not a state the list knows.",
                    new DomainRuleViolation.Remedy("Choose one of the states offered.", "Bursary"));
        }
        if (year != null && (year < 1 || year > 3)) {
            throw new DomainRuleViolation("SPILLOVER_YEAR", "A spillover year is SP1, SP2 or SP3.", new DomainRuleViolation.Remedy("Choose one of them.", "Bursary"));
        }
        OfficeScope.Bound b = scope.bound(fac, dept, prog);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.spillover_students(:s, :fac, :dept, :prog, :y, :st, :q, :lim)")
                .param("s", ses).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("y", year, Types.INTEGER).param("st", st, Types.VARCHAR).param("q", blank(q), Types.VARCHAR)
                .param("lim", Math.max(1, Math.min(limit, 5000))).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", ses);
        out.put("sessions", jdbc.sql("""
                SELECT a.name FROM policy.academic_session a
                 WHERE a.state NOT IN ('DRAFT', 'CANCELLED') AND a.name ~ '^[0-9]{4}/[0-9]{4}$' ORDER BY a.starts_on DESC
                """).query(String.class).list());
        out.put("rows", rows);
        return out;
    }
}
