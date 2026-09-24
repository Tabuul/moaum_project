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

    /** the offices that work within a single department (their screens are bound to it): the Head of
     *  Department, the Examinations Officer, the SIWES Coordinator — and every lecturer, who belongs to one */
    private static final java.util.Set<String> DEPARTMENT_OFFICES = java.util.Set.of("hod", "exams", "siwes", "lecturer");

    /** true when the acting office is the lecturer's */
    public boolean actingLecturer() {
        return AuditContextHolder.current().map(c -> "lecturer".equals(c.actorOffice())).orElse(false);
    }

    /** true when the acting office is the MBBS Coordinator's (V250), an office held by level */
    public boolean actingCoordinator() {
        return AuditContextHolder.current().map(c -> "mbbscoordinator".equals(c.actorOffice())).orElse(false);
    }

    /** the level the acting MBBS Coordinator holds, or null when not acting as one (or the grant names no level) */
    public Integer actingLevel() {
        return AuditContextHolder.current().flatMap(c -> actingCoordinator()
                ? jdbc.sql("SELECT iam.coordinator_level(:p)").param("p", c.actorId()).query(Integer.class).optional()
                : Optional.empty()).orElse(null);
    }

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

    /* ── the guard every scoped endpoint applies: the office's bound on faculty, department and programme ── */

    /** the faculty, department and programme a request is held to */
    public record Bound(String fac, String dept, String prog) {
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private String deptOfProgramme(String prog) {
        return jdbc.sql("SELECT dept_code FROM ref.programme WHERE upper(code) = upper(:p)").param("p", prog).query(String.class).optional().orElse(null);
    }

    private String facultyOfDept(String dept) {
        return jdbc.sql("SELECT faculty_code FROM ref.department WHERE upper(code) = upper(:d)").param("d", dept).query(String.class).optional().orElse(null);
    }

    private static DomainRuleViolation outside(String what, String where) {
        return new DomainRuleViolation("SCOPE_" + where.toUpperCase(), "That " + what + " is not in your " + where + ".",
                new DomainRuleViolation.Remedy("Choose from your own " + where + " in the bar; your office bounds what you see.", "You"));
    }

    /**
     * Holds a request's faculty, department and programme to the acting office's bound, whatever the
     * parameters say. A department office (Head of Department, Examinations Officer, SIWES Coordinator, a
     * lecturer) is held to its own department: a different department or a programme outside it is
     * refused, and an absent department is filled in. A faculty office (Dean, Faculty Officer) is held
     * to its faculty the same way. Every other office is passed through as asked. An office that
     * resolves to nothing is held to a sentinel that matches nothing.
     */
    public Bound bound(String fac, String dept, String prog) {
        fac = blank(fac);
        dept = blank(dept);
        prog = blank(prog);
        if (actingDepartmentOffice()) {
            String own = actingDept();
            if (own == null) own = "__none__";
            if (dept != null && !dept.equalsIgnoreCase(own)) throw outside("department", "department");
            if (prog != null && !own.equalsIgnoreCase(String.valueOf(deptOfProgramme(prog)))) throw outside("programme", "department");
            String f = "__none__".equals(own) ? "__none__" : facultyOfDept(own);
            if (fac != null && f != null && !fac.equalsIgnoreCase(f)) throw outside("faculty", "department");
            return new Bound(f, own, prog);
        }
        if (actingFacultyOffice()) {
            String ownF = actingFaculty();
            if (ownF == null) ownF = "__none__";
            if (fac != null && !fac.equalsIgnoreCase(ownF)) throw outside("faculty", "faculty");
            if (dept != null && !ownF.equalsIgnoreCase(String.valueOf(facultyOfDept(dept)))) throw outside("department", "faculty");
            if (prog != null) {
                String pd = deptOfProgramme(prog);
                if (pd == null || !ownF.equalsIgnoreCase(String.valueOf(facultyOfDept(pd)))) throw outside("programme", "faculty");
            }
            return new Bound(ownF, dept, prog);
        }
        return new Bound(fac, dept, prog);
    }

    /** the department a request is held to: the office's own for a department office, within the faculty for a faculty office */
    public String deptWithin(String requested) {
        return bound(null, requested, null).dept();
    }

    /** a course is read only within the office's bound: its owning department must be in scope */
    public void assertCourseInScope(String courseCode) {
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE upper(code) = upper(:c)").param("c", courseCode == null ? "" : courseCode.trim())
                .query(String.class).optional().orElse(null);
        if (dept == null) return;   // an unknown course is refused downstream as not found, not as out of scope
        bound(null, dept, null);
    }

    /** the offices that work within a single faculty */
    private static final java.util.Set<String> FACULTY_OFFICES = java.util.Set.of("dean", "facultyofficer");

    /** true when the acting office is bound to one faculty (Dean or Faculty Officer) */
    public boolean actingFacultyOffice() {
        return AuditContextHolder.current().map(c -> FACULTY_OFFICES.contains(c.actorOffice())).orElse(false);
    }

    /**
     * The faculty the acting Dean or Faculty Officer works in, or null: the office's own faculty scope,
     * else the faculty of their staff-record home department. The grant may hold the faculty code OR
     * its name — either resolves to the code.
     */
    public String actingFaculty() {
        return AuditContextHolder.current().flatMap(c -> FACULTY_OFFICES.contains(c.actorOffice())
                ? jdbc.sql("""
                        WITH raw AS (
                          SELECT COALESCE(
                            (SELECT scope_id FROM iam.office_assignment
                              WHERE person_id = :p AND office_code IN ('dean','facultyofficer') AND scope_kind = 'faculty'
                                AND nullif(btrim(scope_id), '') IS NOT NULL
                                AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)
                              ORDER BY valid_from DESC LIMIT 1),
                            (SELECT d.faculty_code FROM hrm.staff_record sr JOIN ref.department d ON d.code = sr.home_department
                              WHERE sr.person_id = :p AND nullif(btrim(sr.home_department), '') IS NOT NULL LIMIT 1)
                          ) AS v)
                        SELECT f.code FROM ref.faculty f, raw
                         WHERE raw.v IS NOT NULL
                           AND (upper(btrim(f.code)) = upper(btrim(raw.v)) OR lower(btrim(f.name)) = lower(btrim(raw.v)))
                         LIMIT 1
                        """).param("p", c.actorId()).query(String.class).optional()
                : Optional.empty()).orElse(null);
    }

    /**
     * What a return should be scoped to for the acting office (V229 item 4): a Dean or Faculty Officer
     * sees their faculty, a Head of Department their department; every other office sees the whole
     * University (null). A scoped office that resolves to nothing gets a sentinel that matches nothing.
     */
    public record ReportScope(String facultyCode, String facultyName, String departmentCode, String departmentName,
                              java.util.Set<String> programmeNames) {
        public String label() {
            return departmentName != null ? "Department of " + departmentName : facultyName != null ? "Faculty of " + facultyName : "";
        }
    }

    public ReportScope reportScope() {
        if (actingDepartmentOffice()) {
            String d = actingDept();
            if (d == null) return new ReportScope("__none__", "__none__", "__none__", "__none__", java.util.Set.of());
            var row = jdbc.sql("""
                    SELECT d.code, d.name, f.code AS faculty_code, f.name AS faculty_name,
                           coalesce((SELECT array_agg(p.name) FROM ref.programme p WHERE p.dept_code = d.code), '{}') AS programmes
                      FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code WHERE d.code = :d
                    """).param("d", d).query().singleRow();
            String[] progs = (String[]) toArray(row.get("programmes"));
            return new ReportScope((String) row.get("faculty_code"), (String) row.get("faculty_name"),
                    (String) row.get("code"), (String) row.get("name"), java.util.Set.of(progs));
        }
        if (actingFacultyOffice()) {
            String f = actingFaculty();
            if (f == null) return new ReportScope("__none__", "__none__", null, null, java.util.Set.of());
            String name = jdbc.sql("SELECT name FROM ref.faculty WHERE code = :f").param("f", f).query(String.class).single();
            return new ReportScope(f, name, null, null, null);
        }
        return null;
    }

    private static Object toArray(Object pgArray) {
        try {
            if (pgArray instanceof java.sql.Array a) return a.getArray();
        } catch (java.sql.SQLException ignored) { /* fall through */ }
        return pgArray instanceof String[] s ? s : new String[0];
    }
}
