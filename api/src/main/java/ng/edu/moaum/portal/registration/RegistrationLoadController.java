package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The minimum course registration load by curriculum (V495): CCMAS and BMAS each have a standing minimum, and a session's or a
 * semester's own where it differs. The Directorate of ICT (and super) sets it with a reason; each change is logged with the value
 * before and after. The registration engine reads it at every submission, add and drop (registration.unit_rule) — the student's
 * curriculum is the student's own record, never a value from the browser — and a registration already made is never rewritten.
 * The Academic Office, the Registry and admin read it, with the registrations of a session below the minimum that binds them.
 */
@RestController
@RequestMapping("/api/v1/registration/load")
class RegistrationLoadController {

    static final String SETTERS = "hasAnyAuthority('OFFICE_ict','OFFICE_super')";
    static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    RegistrationLoadController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private static String session(String s, boolean required) {
        if (s == null || s.isBlank()) {
            if (!required) return null;
        } else if (s.trim().matches("\\d{4}/\\d{4}")) {
            return s.trim();
        }
        throw new DomainRuleViolation("REG_MIN_UNITS_SESSION", "A session is named YYYY/YYYY.", new DomainRuleViolation.Remedy("Choose the session.", "Directorate of ICT"));
    }

    private static Integer semester(Integer m) {
        if (m != null && (m < 1 || m > 3)) {
            throw new DomainRuleViolation("REG_MIN_UNITS_SEMESTER", "A semester is 1, 2 or 3.",
                    new DomainRuleViolation.Remedy("Choose the semester, or every semester.", "Directorate of ICT"));
        }
        return m;
    }

    /** the minimum in force for each curriculum in a session (and semester), every rule set, the undergraduate maxima it may not
     *  pass, and the changes made */
    @GetMapping("/rules")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rules(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        String current = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
        String s = session(session, false);
        if (s == null) s = current;
        Integer m = semester(semester);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", m);
        out.put("current", current);
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 12").query(String.class).list());
        out.put("inForce", jdbc.sql("""
                SELECT f.curriculum, f.min_units, f.applies_as, f.rule_session, f.rule_semester, f.reason, f.set_at, helpdesk.person_name(f.set_by) AS set_by,
                       f.set_office, f.students
                  FROM registration.unit_minimum_in_force(:s, :m) f
                """).param("s", s, Types.VARCHAR).param("m", m, Types.INTEGER).query().listOfRows());
        out.put("rules", jdbc.sql("""
                SELECT u.id, u.curriculum, u.session, u.semester, u.min_units, u.reason, u.set_at, helpdesk.person_name(u.set_by) AS set_by, u.set_office
                  FROM registration.unit_minimum u ORDER BY u.session NULLS FIRST, u.semester NULLS FIRST, u.curriculum DESC
                """).query().listOfRows());
        out.put("maxima", jdbc.sql("SELECT level, applies_to, min_units, max_units FROM policy.level_limit WHERE level BETWEEN 100 AND 600 ORDER BY level")
                .query().listOfRows());
        out.put("history", jdbc.sql("""
                SELECT c.id, c.event, c.curriculum, c.session, c.semester, c.before_units, c.after_units, c.reason, c.changed_at,
                       helpdesk.person_name(c.changed_by) AS changed_by, c.changed_office
                  FROM registration.unit_minimum_change c ORDER BY c.changed_at DESC LIMIT 100
                """).query().listOfRows());
        return out;
    }

    public record RuleIn(@NotBlank @Size(max = 10) String curriculum, @Size(max = 9) String session, Integer semester, Integer minUnits,
                         @NotBlank @Size(max = 2000) String reason) {
    }

    /** set the minimum of a curriculum — the standing rule (no session), a session's, or a semester's within a session */
    @PutMapping("/rules")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> setRule(@Valid @RequestBody RuleIn body) {
        if (body.minUnits() == null) {
            throw new DomainRuleViolation("REG_MIN_UNITS_NUMBER", "Minimum credit units must be a whole number.",
                    new DomainRuleViolation.Remedy("Enter the number of credit units.", "Directorate of ICT"));
        }
        if (body.minUnits() < 1) {
            throw new DomainRuleViolation("REG_MIN_UNITS_POSITIVE", "Minimum credit units must be greater than zero.",
                    new DomainRuleViolation.Remedy("Enter a number of credit units from 1.", "Directorate of ICT"));
        }
        String s = session(body.session(), false);
        Integer m = semester(body.semester());
        jdbc.sql("SELECT registration.set_unit_minimum(:c, :s, :m, :u, :r)").param("c", body.curriculum().trim().toUpperCase()).param("s", s, Types.VARCHAR)
                .param("m", m, Types.INTEGER).param("u", body.minUnits()).param("r", body.reason().trim()).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(rules(s, m));
        out.put("told", tell(body.curriculum(), s, m));
        return out;
    }

    public record RemoveIn(@NotBlank @Size(max = 10) String curriculum, @NotBlank @Size(max = 9) String session, Integer semester,
                           @NotBlank @Size(max = 2000) String reason) {
    }

    /** remove a session's or a semester's own minimum: the session's (or the standing) rule applies again */
    @PostMapping("/rules/remove")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> removeRule(@Valid @RequestBody RemoveIn body) {
        String s = session(body.session(), true);
        Integer m = semester(body.semester());
        int n = jdbc.sql("SELECT registration.set_unit_minimum(:c, :s, :m, NULL, :r)").param("c", body.curriculum().trim().toUpperCase()).param("s", s)
                .param("m", m, Types.INTEGER).param("r", body.reason().trim()).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>(rules(s, m));
        out.put("removed", n);
        out.put("told", tell(body.curriculum(), s, m));
        return out;
    }

    /** V505: the students whose draft, returned or submitted registration the minimum now in force leaves short, told (once for
     *  each minimum); a registration approved earlier is neither rewritten nor told */
    private int tell(String curriculum, String session, Integer semester) {
        return jdbc.sql("SELECT registration.tell_unit_minimum_change(:c, :s, :m)").param("c", curriculum.trim().toUpperCase()).param("s", session, Types.VARCHAR)
                .param("m", semester, Types.INTEGER).query(Integer.class).single();
    }

    /** V505: before a change is confirmed — by status, the registrations a minimum of {@code minUnits} would leave below it */
    @GetMapping("/impact")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> impact(@RequestParam String curriculum, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                               @RequestParam int minUnits) {
        if (minUnits < 1) throw new DomainRuleViolation("REG_MIN_UNITS_POSITIVE", "Minimum credit units must be greater than zero.");
        String s = session(session, false);
        Integer m = semester(semester);
        java.util.List<Map<String, Object>> rows = jdbc.sql("SELECT status, registrations FROM registration.unit_minimum_impact(:c, :s, :m, :u)")
                .param("c", curriculum.trim().toUpperCase()).param("s", s, Types.VARCHAR).param("m", m, Types.INTEGER).param("u", minUnits).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        Map<String, Object> by = new LinkedHashMap<>();
        long notYet = 0, approved = 0;
        for (Map<String, Object> r : rows) {
            long k = ((Number) r.get("registrations")).longValue();
            by.put(String.valueOf(r.get("status")), k);
            if (java.util.Set.of("DRAFT", "RETURNED", "SUBMITTED").contains(String.valueOf(r.get("status")))) notYet += k; else approved += k;
        }
        out.put("byStatus", by);
        out.put("toTell", notYet);
        out.put("approvedKept", approved);
        return out;
    }

    /** the registrations of a session (and semester) carrying fewer units than the minimum that binds the student */
    @GetMapping("/below-minimum")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> belowMinimum(@RequestParam String session, @RequestParam(required = false) Integer semester,
                                     @RequestParam(required = false) String curriculum, @RequestParam(defaultValue = "0") int page,
                                     @RequestParam(defaultValue = "50") int size) {
        String s = session(session, true);
        Integer m = semester(semester);
        String c = curriculum == null || curriculum.isBlank() ? null : curriculum.trim().toUpperCase();
        int sz = Math.max(1, Math.min(size, 2000));
        int pg = Math.max(0, page);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", m);
        java.util.List<Map<String, Object>> all = jdbc.sql("""
                SELECT b.* FROM registration.below_minimum(:s, :m) b
                 WHERE (CAST(:c AS text) IS NULL OR b.curriculum = CAST(:c AS text))
                 ORDER BY b.programme, b.level, b.full_name
                """).param("s", s).param("m", m, Types.INTEGER).param("c", c, Types.VARCHAR).query().listOfRows();
        out.put("total", all.size());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", all.subList(Math.min(all.size(), pg * sz), Math.min(all.size(), (pg + 1) * sz)));
        return out;
    }
}
