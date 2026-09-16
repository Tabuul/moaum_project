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

    /** true when the request is being made in the Head-of-Department office */
    public boolean actingHod() {
        return AuditContextHolder.current().map(c -> "hod".equals(c.actorOffice())).orElse(false);
    }

    /** the acting person, or null */
    public UUID actorId() {
        return AuditContextHolder.current().map(AuditContext::actorId).orElse(null);
    }

    /** the department the acting HOD heads, or null (not acting as HOD, or no HOD grant) */
    public String actingHodDept() {
        return AuditContextHolder.current().flatMap(c -> "hod".equals(c.actorOffice())
                ? jdbc.sql("""
                        SELECT scope_id FROM iam.office_assignment
                         WHERE person_id = :p AND office_code = 'hod' AND scope_kind = 'department'
                           AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                         LIMIT 1
                        """).param("p", c.actorId()).query(String.class).optional()
                : Optional.empty()).orElse(null);
    }

    /**
     * The department a screen should be scoped to. When the request is an HOD's,
     * it is their own department (or a sentinel that matches nothing when they
     * hold no HOD grant), so a department parameter they send is ignored; for any
     * other office the requested department stands.
     */
    public String scopedDept(String requested) {
        if (!actingHod()) {
            return requested;
        }
        String own = actingHodDept();
        return own != null ? own : "__none__";
    }
}
