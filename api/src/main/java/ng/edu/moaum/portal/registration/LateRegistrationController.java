package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V516: late registration by the Registry, on the student's behalf. The Registry finds the student by matriculation or admission
 * number, sees the student's own list of courses for the semester with what the engine says of each (registration.registry_late_checks:
 * the registration window and the add and drop period are set aside for a late registration, every other rule holds), and registers
 * the courses chosen with a reason (registration.registry_register: added and submitted by the ICT Support engine, approved by the
 * semester's rule or left for the Head of Department, recorded, the student told). The Academic Office reads it.
 */
@RestController
@RequestMapping("/api/v1/registration/late")
class LateRegistrationController {

    static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_super')";
    static final String REGISTRY = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    private final JdbcClient jdbc;

    LateRegistrationController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    private String session(String s) {
        if (s == null || s.isBlank()) {
            return jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional()
                    .orElseThrow(() -> new DomainRuleViolation("REG_LATE_SESSION", "No session is current; choose one."));
        }
        if (!s.trim().matches("\\d{4}/\\d{4}")) {
            throw new DomainRuleViolation("REG_LATE_SESSION", "A session is named YYYY/YYYY.", new DomainRuleViolation.Remedy("Choose the session.", "Registry"));
        }
        return s.trim();
    }

    private static int semester(Integer m) {
        if (m == null) return 1;
        if (m < 1 || m > 3) throw new DomainRuleViolation("REG_LATE_SEMESTER", "A semester is 1, 2 or 3.");
        return m;
    }

    /** the student by matriculation or admission number, with the semester's registration, load, window and fees, and the student's own
     *  list of courses with what the engine says of each for a late registration */
    @GetMapping("/student")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@RequestParam String number, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        String s = session(session);
        int m = semester(semester);
        String no = number == null ? "" : number.trim().toUpperCase(Locale.ROOT);
        List<Map<String, Object>> found = jdbc.sql("""
                SELECT x.id, upper(btrim(x.surname)) || coalesce(', ' || nullif(btrim(x.other_names), ''), '') AS name, x.matric_no, x.admission_no,
                       x.status, x.current_level, x.entry_mode, p.name AS programme, p.dept_code
                  FROM people.student x LEFT JOIN ref.programme p ON p.code = x.programme_code
                 WHERE upper(btrim(x.matric_no)) = :n OR upper(btrim(x.admission_no)) = :n
                 LIMIT 2
                """).param("n", no).query().listOfRows();
        if (found.isEmpty()) {
            throw new DomainRuleViolation("REG_LATE_NO_STUDENT", "No student has the number " + no + ".",
                    new DomainRuleViolation.Remedy("Use the matriculation or the admission number, as on the student's record.", "Registry"));
        }
        Map<String, Object> st = found.get(0);
        UUID id = (UUID) st.get("id");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", m);
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 12").query(String.class).list());
        out.put("student", st);
        out.put("registration", jdbc.sql("""
                SELECT r.id, r.status, r.level, r.submitted_at, r.approved_at, registration.units_of(r.id) AS units
                  FROM registration.course_registration r WHERE r.student_id = :st AND r.session = :s AND r.semester = :m
                """).param("st", id).param("s", s).param("m", m).query().listOfRows().stream().findFirst().orElse(null));
        int level = ((Number) st.get("current_level")).intValue();
        out.put("load", jdbc.sql("SELECT min_units, max_units, basis, curriculum FROM registration.unit_rule(:st, :l, :s, :m)")
                .param("st", id).param("l", level).param("s", s).param("m", m).query().listOfRows().stream().findFirst().orElse(null));
        out.put("window", jdbc.sql("SELECT registration.registration_gate(:st, :s, :m)").param("st", id).param("s", s).param("m", m).query(String.class).optional().orElse(null));
        out.put("feesCleared", jdbc.sql("SELECT finance.clears_or_null(:st, :s, 'REGISTRATION')").param("st", id).param("s", s).query(Boolean.class).optional().orElse(null));
        List<Map<String, Object>> menu = jdbc.sql("""
                SELECT m.offering_id, m.course_code, m.title, m.units, m.kind, m.basis, m.carryover, m.deferred,
                       EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                                WHERE r.student_id = :st AND r.session = :s AND r.semester = :m AND e.offering_id = m.offering_id
                                  AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) AS registered,
                       (SELECT c.message FROM registration.registry_late_checks(:st, :s, :m, m.offering_id) c WHERE c.blocks ORDER BY c.ord LIMIT 1) AS blocked_by,
                       EXISTS (SELECT 1 FROM registration.registry_late_checks(:st, :s, :m, m.offering_id) c WHERE c.set_aside) AS window_set_aside
                  FROM registration.student_menu(:st, :s, :m) m
                 ORDER BY m.carryover DESC, m.course_code
                """).param("st", id).param("s", s).param("m", m).query().listOfRows();
        out.put("menu", menu);
        out.put("history", jdbc.sql("""
                SELECT l.at, l.semester, l.units, l.status, l.reason, cardinality(l.offerings) AS courses,
                       (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = l.by_person) AS by_name, l.by_office
                  FROM registration.late_registration l WHERE l.student_id = :st ORDER BY l.at DESC
                """).param("st", id).query().listOfRows());
        return out;
    }

    public record LateIn(@NotNull UUID studentId, @NotBlank @Size(max = 9) String session, @Min(1) @Max(3) int semester,
                         @NotEmpty @Size(max = 40) List<UUID> offerings, @NotBlank @Size(min = 10, max = 1000) String reason) {
    }

    /** the courses chosen registered late and the registration submitted, with the Registry's reason (the database holds every rule) */
    @PostMapping
    @PreAuthorize(REGISTRY)
    @Transactional
    Object register(@Valid @RequestBody LateIn body) {
        String offerings = "{" + String.join(",", body.offerings().stream().map(UUID::toString).toList()) + "}";
        String out = jdbc.sql("SELECT registration.registry_register(:st, :s, :m, CAST(:o AS uuid[]), :r)::text").param("st", body.studentId()).param("s", session(body.session()))
                .param("m", body.semester()).param("o", offerings).param("r", body.reason().trim()).query(String.class).single();
        return new tools.jackson.databind.ObjectMapper().readValue(out, Map.class);
    }

    /** the late registrations of a session (and semester), newest first */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql("""
                SELECT l.id, l.at, l.semester, l.units, l.status, l.reason, cardinality(l.offerings) AS courses, l.by_office,
                       (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = l.by_person) AS by_name,
                       x.id AS student_id, upper(btrim(x.surname)) || coalesce(', ' || nullif(btrim(x.other_names), ''), '') AS name, coalesce(x.matric_no, x.admission_no) AS number,
                       p.name AS programme, p.dept_code
                  FROM registration.late_registration l JOIN people.student x ON x.id = l.student_id LEFT JOIN ref.programme p ON p.code = x.programme_code
                 WHERE l.session = :s AND (CAST(:m AS integer) IS NULL OR l.semester = CAST(:m AS integer))
                 ORDER BY l.at DESC LIMIT 500
                """).param("s", s).param("m", semester, Types.INTEGER).query().listOfRows());
        return out;
    }
}
