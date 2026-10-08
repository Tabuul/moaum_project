package ng.edu.moaum.portal.finance;

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
 * V362: the course registrations of a session made without the semester's school fees cleared — the fees not stated for
 * the student, or stated and not paid — for the Bursary and the Registry to act on. Read only: nothing about a
 * registration or a payment changes here; what is done about each is the Bursary's and the Registry's own act.
 */
@RestController
@RequestMapping("/api/v1/finance/registrations-without-fees")
class UnpaidRegistrationsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_academic','OFFICE_audit','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc')";

    private final JdbcClient jdbc;

    UnpaidRegistrationsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session) {
        String s = session == null || session.isBlank()
                ? jdbc.sql("SELECT name FROM policy.academic_session ORDER BY (state = 'CURRENT') DESC, (now()::date BETWEEN starts_on AND ends_on) DESC, starts_on DESC LIMIT 1")
                        .query(String.class).optional().orElse(null)
                : session.trim();
        if (s == null || !s.matches("^[0-9]{4}/[0-9]{4}$")) {
            throw new DomainRuleViolation("FIN_SESSION", "Name the session, such as 2026/2027.");
        }
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.registrations_without_fees(:s)").param("s", s).query().listOfRows();
        long notStated = rows.stream().filter(r -> !Boolean.TRUE.equals(r.get("stated"))).count();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("scheduleFrom", jdbc.sql("SELECT finance.schedule_from()").query(String.class).optional().orElse(null));
        out.put("total", rows.size());
        out.put("notStated", notStated);
        out.put("unpaid", rows.size() - notStated);
        out.put("rows", rows);
        out.put("sessions", jdbc.sql("SELECT DISTINCT session FROM registration.course_registration ORDER BY session DESC LIMIT 12").query(String.class).list());
        return out;
    }
}
