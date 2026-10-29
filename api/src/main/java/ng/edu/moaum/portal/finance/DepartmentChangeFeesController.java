package ng.edu.moaum.portal.finance;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V702: the students held a level behind after a change of department (V696), for the Bursary. They are charged the held level's fee
 * (the University's word of 29 October 2026); beside it, what the session would charge without the hold — read with the hold lifted
 * and undone (finance.department_change_fee_effect), so nothing on a record changes. Not read-only: the reading writes and undoes.
 */
@RestController
@RequestMapping("/api/v1/finance/department-change-fees")
class DepartmentChangeFeesController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic',"
            + "'OFFICE_audit','OFFICE_deputyaudit','OFFICE_ict','OFFICE_super')";

    private final JdbcClient jdbc;

    DepartmentChangeFeesController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> list(@RequestParam(required = false) String session) {
        String s = session != null && session.trim().matches("[0-9]{4}/[0-9]{4}") ? session.trim()
                : jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
        if (s == null) throw new DomainRuleViolation("HELD_FEES_SESSION", "No session is current; choose one.");
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT f.student_id AS "studentId", f.number, f.student_name AS "studentName", f.programme_code AS "programmeCode", pr.name AS programme,
                       pr.dept_code AS "deptCode", pr.faculty_code AS "facultyCode", f.held_level AS "heldLevel", f.unheld_level AS "unheldLevel",
                       f.held_spillover AS "heldSpillover", f.charged_held AS "chargedHeld", f.charged_unheld AS "chargedUnheld", f.difference
                  FROM finance.department_change_fee_effect(:s) f LEFT JOIN ref.programme pr ON pr.code = f.programme_code
                """).param("s", s).query().listOfRows();
        BigDecimal held = BigDecimal.ZERO, unheld = BigDecimal.ZERO, more = BigDecimal.ZERO, less = BigDecimal.ZERO;
        int higher = 0, lower = 0;
        for (Map<String, Object> r : rows) {
            BigDecimal h = (BigDecimal) r.get("chargedHeld"), u = (BigDecimal) r.get("chargedUnheld"), d = (BigDecimal) r.get("difference");
            held = held.add(h);
            unheld = unheld.add(u);
            if (d.signum() > 0) { more = more.add(d); higher++; }
            if (d.signum() < 0) { less = less.add(d.negate()); lower++; }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("students", rows.size());
        out.put("chargedHeld", held);
        out.put("chargedUnheld", unheld);
        out.put("higher", higher);
        out.put("higherBy", more);
        out.put("lower", lower);
        out.put("lowerBy", less);
        out.put("rows", rows);
        return out;
    }
}
