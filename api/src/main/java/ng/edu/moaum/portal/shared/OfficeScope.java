package ng.edu.moaum.portal.shared;

import java.util.Optional;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Scopes what a request may see to the office it is made in. A Head of Department
 * works within one department: their catalogue, their allocation, their courses.
 * The active office comes from the audit context (the X-Active-Office the request
 * carried); the department is the scope of their standing 'hod' grant.
 */
@Component
public class OfficeScope {

    private final JdbcClient jdbc;

    OfficeScope(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the offices that work within a single department (their screens are bound to it) */
    private static final java.util.Set<String> DEPARTMENT_OFFICES = java.util.Set.of("hod", "siwes");

    /** true when the request is being made in the Head-of-Department office */
    public boolean actingHod() {
        return AuditContextHolder.current().map(c -> "hod".equals(c.actorOffice())).orElse(false);
    }

    /** true when the acting office is bound to one department (Head of Department or SIWES Coordinator) */
    public boolean actingDepartmentOffice() {
        return AuditContextHolder.current().map(c -> DEPARTMENT_OFFICES.contains(c.actorOffice())).orElse(false);
    }

    /** the acting person, or null */
    public UUID actorId() {
        return AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
    }

    /**
     * The department the acting HOD heads, or null (not acting as HOD, or no department can be
     * resolved). See {@link #actingDept()} for how the department is resolved.
     */
    public String actingHodDept() {
        return actingHod() ? actingDept() : null;
    }

    /**
     * The department the acting department-office (Head of Department or SIWES Coordinator) works in,
     * or null. The department is taken, in order of authority, from: the acting office's own
     * department scope; failing that, the person's home department as a lecturer (every teacher is on
     * the establishment scoped to their department, V135/V137); failing that, the home department on
     * their staff record. The grant may hold the department code OR its name — either resolves to the
     * code. The fallbacks mean an office created without a department scope still works.
     */
    public String actingDept() {
        return AuditContextHolder.current().flatMap(c -> DEPARTMENT_OFFICES.contains(c.actorOffice())
                ? jdbc.sql("""
                        WITH raw AS (
                          SELECT COALESCE(
                            (SELECT scope_id FROM iam.office_assignment
                              WHERE person_id = :p AND office_code = :office AND scope_kind = 'department'
                                AND nullif(btrim(scope_id), '') IS NOT NULL
                                AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                              ORDER BY valid_from DESC LIMIT 1),
                            (SELECT scope_id FROM iam.office_assignment
                              WHERE person_id = :p AND office_code = 'lecturer' AND scope_kind = 'department'
                                AND nullif(btrim(scope_id), '') IS NOT NULL
                                AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                              ORDER BY valid_from DESC LIMIT 1),
                            (SELECT home_department FROM hrm.staff_record
                              WHERE person_id = :p AND nullif(btrim(home_department), '') IS NOT NULL LIMIT 1)
                          ) AS v)
                        SELECT d.code FROM ref.department d, raw
                         WHERE raw.v IS NOT NULL AND d.ended_on IS NULL
                           AND (upper(btrim(d.code)) = upper(btrim(raw.v)) OR lower(btrim(d.name)) = lower(btrim(raw.v)))
                         LIMIT 1
                        """).param("p", c.actorId()).param("office", c.actorOffice()).query(String.class).optional()
                : Optional.empty()).orElse(null);
    }

    /**
     * The department a screen should be scoped to. When the request is a department office's (HOD or
     * SIWES Coordinator), it is their own department (or a sentinel that matches nothing when none can
     * be resolved), so a department parameter they send is ignored; for any other office the requested
     * department stands.
     */
    public String scopedDept(String requested) {
        if (!actingDepartmentOffice()) {
            return requested;
        }
        String own = actingDept();
        return own != null ? own : "__none__";
    }
}
