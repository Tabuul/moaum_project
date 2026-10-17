package ng.edu.moaum.portal.registration;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V508: overload approval. The student asks for a higher maximum course load for one semester, with a reason (more than the
 * maximum, at most the Academic Office's extra above it), sees where the request stands and withdraws it while it waits; the Head
 * of Department of the student's department grants a ceiling (which registration.unit_rule then reads as the semester's maximum,
 * for every check) or refuses, with a reason; the Academic Office, the Registry and the Dean read the requests. The database holds
 * every rule (registration.request_overload, decide_overload, withdraw_overload, overload_state); the student is the token's, never
 * a number the browser sends.
 */
@RestController
@RequestMapping("/api/v1")
class OverloadController {

    static final String STUDENT = "hasAuthority('OFFICE_student')";
    static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    static final String DECIDERS = "hasAnyAuthority('OFFICE_hod','OFFICE_super')";
    static final String RULE_SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_super')";
    static final Set<String> STATUSES = Set.of("REQUESTED", "GRANTED", "REFUSED", "WITHDRAWN");
    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    OverloadController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static String session(String s) {
        if (s == null || !s.trim().matches("\\d{4}/\\d{4}")) {
            throw new DomainRuleViolation("REG_OVERLOAD_SESSION", "A session is named YYYY/YYYY.", new DomainRuleViolation.Remedy("Choose the session.", "You"));
        }
        return s.trim();
    }

    private static Integer semester(Integer m) {
        if (m != null && (m < 1 || m > 3)) {
            throw new DomainRuleViolation("REG_OVERLOAD_SEMESTER", "A semester is 1, 2 or 3.", new DomainRuleViolation.Remedy("Choose the semester.", "You"));
        }
        return m;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(String s) {
        return s == null ? null : JSON.readValue(s, Map.class);
    }

    /* ── the student ── */

    /** where the student stands for the semester: the request (the live one first), the maximum, the ceiling a grant may reach,
     *  and whether they may ask (and why not) */
    @GetMapping("/me/overload")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth, @RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        return json(jdbc.sql("SELECT registration.overload_state(:st, :s, :m)::text").param("st", UUID.fromString(auth.getName()))
                .param("s", session(session)).param("m", semester(semester)).query(String.class).single());
    }

    public record AskIn(@NotBlank @Size(max = 9) String session, @Min(1) @Max(3) int semester, @Min(1) @Max(60) int units,
                        @NotBlank @Size(min = 10, max = 1000) String reason) {
    }

    @PostMapping("/me/overload")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> ask(Authentication auth, @Valid @RequestBody AskIn body) {
        UUID student = UUID.fromString(auth.getName());
        UUID id = jdbc.sql("SELECT registration.request_overload(:st, :s, :m, :u, :r)").param("st", student).param("s", session(body.session()))
                .param("m", body.semester()).param("u", body.units()).param("r", body.reason().trim()).query(UUID.class).single();
        return json(jdbc.sql("SELECT registration.overload_state(:st, :s, :m)::text").param("st", student).param("s", body.session().trim())
                .param("m", body.semester()).query(String.class).single());
    }

    @PostMapping("/me/overload/{id}/withdraw")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> withdraw(Authentication auth, @PathVariable UUID id) {
        String s = jdbc.sql("SELECT registration.withdraw_overload(:st, :id)").param("st", UUID.fromString(auth.getName())).param("id", id).query(String.class).single();
        return Map.of("id", id, "status", s);
    }

    /* ── the offices ── */

    /** the requests of a session (and semester), the Head of Department's own department, the Dean's own faculty, everyone's for the
     *  Academic Office and the Registry; with the counts by status */
    @GetMapping("/registration/overloads")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                             @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String current = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
        String s = session == null || session.isBlank() ? current : session(session);
        if (s == null) throw new DomainRuleViolation("REG_OVERLOAD_SESSION", "No session is current; choose one.");
        Integer m = semester(semester);
        String st = status == null || status.isBlank() ? null : status.trim().toUpperCase(Locale.ROOT);
        if (st != null && !STATUSES.contains(st)) throw new DomainRuleViolation("REG_OVERLOAD_STATUS", "That is not a request's status.");
        String t = q == null || q.isBlank() ? null : "%" + q.trim().toUpperCase(Locale.ROOT) + "%";
        OfficeScope.Bound b = scope.bound(null, null, null);
        String from = """
                  FROM registration.overload_request r
                  JOIN people.student s ON s.id = r.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE r.session = :s AND (CAST(:m AS integer) IS NULL OR r.semester = CAST(:m AS integer))
                   AND (CAST(:dept AS text) IS NULL OR p.dept_code = CAST(:dept AS text))
                   AND (CAST(:fac AS text) IS NULL OR coalesce(d.faculty_code, p.faculty_code) = CAST(:fac AS text))
                   AND (CAST(:t AS text) IS NULL OR upper(s.surname || ' ' || coalesce(s.other_names, '')) LIKE CAST(:t AS text)
                        OR upper(coalesce(s.matric_no, s.admission_no, '')) LIKE CAST(:t AS text))
                """;
        Map<String, Object> counts = new LinkedHashMap<>();
        for (String k : List.of("REQUESTED", "GRANTED", "REFUSED", "WITHDRAWN")) counts.put(k, 0L);
        jdbc.sql("SELECT r.status, count(*) AS n " + from + " GROUP BY r.status").param("s", s).param("m", m, Types.INTEGER)
                .param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).param("t", t, Types.VARCHAR)
                .query().listOfRows().forEach(r -> counts.put(String.valueOf(r.get("status")), r.get("n")));
        int sz = Math.max(1, Math.min(size, 5000)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.id, r.student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name,
                       coalesce(s.matric_no, s.admission_no) AS matric_no, p.name AS programme, p.dept_code, coalesce(d.faculty_code, p.faculty_code) AS faculty_code,
                       r.session, r.semester, r.level, r.regular_max, r.requested_max, r.granted_max, r.reason, r.status, r.decision_reason,
                       r.requested_at, r.decided_at, r.decided_office,
                       -- V514: whether the student's department has a Head on the portal to decide it
                       EXISTS (SELECT 1 FROM registration.department_heads(p.dept_code)) AS has_head,
                       (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = r.decided_by) AS decided_by,
                       (SELECT registration.units_of(g.id) FROM registration.course_registration g
                         WHERE g.student_id = r.student_id AND g.session = r.session AND g.semester = r.semester) AS units
                """ + from + " AND (CAST(:st AS text) IS NULL OR r.status = CAST(:st AS text))"
                + " ORDER BY (r.status = 'REQUESTED') DESC, r.requested_at DESC LIMIT :lim OFFSET :off")
                .param("s", s).param("m", m, Types.INTEGER).param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR)
                .param("t", t, Types.VARCHAR).param("st", st, Types.VARCHAR).param("lim", sz).param("off", pg * sz).query().listOfRows();
        long total = st == null ? counts.values().stream().mapToLong(v -> ((Number) v).longValue()).sum() : ((Number) counts.get(st)).longValue();
        // V514: the waiting requests no Head of Department on the portal can decide (their department has none)
        long noHead = jdbc.sql("SELECT count(*) " + from + " AND r.status = 'REQUESTED' AND NOT EXISTS (SELECT 1 FROM registration.department_heads(p.dept_code))")
                .param("s", s).param("m", m, Types.INTEGER).param("dept", b.dept(), Types.VARCHAR).param("fac", b.fac(), Types.VARCHAR).param("t", t, Types.VARCHAR)
                .query(Long.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", m);
        out.put("current", current);
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 12").query(String.class).list());
        out.put("dept", b.dept());
        out.put("faculty", b.fac());
        out.put("counts", counts);
        out.put("noHead", noHead);
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("rule", rule());
        return out;
    }

    public record DecideIn(@NotBlank String decision, @Min(1) @Max(60) Integer units, @NotBlank @Size(min = 10, max = 1000) String reason) {
    }

    /** the Head of Department of the student's department grants a ceiling, or refuses, with a reason (the database checks the
     *  department, the ceiling and that the request still waits) */
    @PostMapping("/registration/overloads/{id}/decide")
    @PreAuthorize(DECIDERS)
    @Transactional
    Map<String, Object> decide(@PathVariable UUID id, @Valid @RequestBody DecideIn body) {
        String d = body.decision().trim().toUpperCase(Locale.ROOT);
        if ("GRANTED".equals(d) && body.units() == null) {
            throw new DomainRuleViolation("REG_OVERLOAD_UNITS", "A grant names the ceiling, in credit units.", new DomainRuleViolation.Remedy("Enter the most the student may register this semester.", "Head of Department"));
        }
        String out = jdbc.sql("SELECT registration.decide_overload(:id, :d, :u, :r)").param("id", id).param("d", d).param("u", body.units(), Types.INTEGER)
                .param("r", body.reason().trim()).query(String.class).single();
        return Map.of("id", id, "status", out);
    }

    /** the rule: whether students ask, and how far above the maximum a grant may go */
    @GetMapping("/registration/overloads/rule")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rule() {
        return jdbc.sql("""
                SELECT p.open, p.max_extra, p.reason, p.set_at, p.set_office,
                       (SELECT btrim(pe.surname || ', ' || pe.given_names) FROM iam.person pe WHERE pe.id = p.set_by) AS set_by
                  FROM registration.overload_rule() p
                """).query().singleRow();
    }

    public record RuleIn(@NotNull Boolean open, @Min(1) @Max(12) int maxExtra, @NotBlank @Size(min = 10, max = 500) String reason) {
    }

    @PutMapping("/registration/overloads/rule")
    @PreAuthorize(RULE_SETTERS)
    @Transactional
    Map<String, Object> setRule(@Valid @RequestBody RuleIn body) {
        jdbc.sql("SELECT registration.set_overload_policy(:o, :x, :r)").param("o", body.open()).param("x", body.maxExtra()).param("r", body.reason().trim()).query().listOfRows();
        return rule();
    }
}
