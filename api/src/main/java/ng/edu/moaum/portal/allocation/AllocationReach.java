package ng.edu.moaum.portal.allocation;

import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Which classes the acting office may work on the allocation desks, and with what (V408). The Director of ICT, the Head of the
 * ICT Support Desk, Admin and Super reach every class of the University. An ICT Support Agent (a CPO) reaches only the
 * faculties and departments of the postings that carry the capability — helpdesk.agent_scope_for, the support desk's own
 * scope rule — so a capability granted on a faculty posting never reaches past that faculty, and an agent whose postings
 * carry none reaches nothing. The academic offices keep their own bound (OfficeScope): a Head of Department their
 * department, a faculty office its faculty, the Registry the University. Every desk endpoint asks here on the server; the
 * screen's buttons only follow.
 */
@Component
class AllocationReach {

    static final String VIEW = "VIEW_ALLOCATIONS";
    static final String ALLOCATE = "ALLOCATE_COURSES";
    static final String REMOVE = "REMOVE_ALLOCATIONS";
    static final String BULK = "BULK_ALLOCATE";
    static final List<String> ALL = List.of(VIEW, ALLOCATE, REMOVE, BULK);

    /** the offices that hold every allocation capability over the University */
    private static final Set<String> WHOLE = Set.of("ict", "helpdeskhead", "admin", "super");
    private static final Map<String, String> WORDS = Map.of(VIEW, "viewing course allocations", ALLOCATE, "allocating and reassigning lecturers",
            REMOVE, "removing a co-lecturer", BULK, "bulk course allocation");

    /** the University (all), or these faculties and departments; words says which, for the screen */
    record Reach(boolean all, Set<String> faculties, Set<String> departments, String words) {
        boolean none() {
            return !all && faculties.isEmpty() && departments.isEmpty();
        }

        boolean covers(String faculty, String dept) {
            if (all) return true;
            return (faculty != null && faculties.contains(faculty.toUpperCase())) || (dept != null && departments.contains(dept.toUpperCase()));
        }
    }

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    AllocationReach(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    static UUID actor() {
        return AuditContextHolder.current().map(c -> c.actorId()).orElse(null);
    }

    /** an ICT Support Agent, whose reach comes from their postings */
    static boolean agent() {
        return "ictagent".equals(office());
    }

    /** where the acting office reaches with this capability */
    Reach of(String capability) {
        String office = office();
        if (WHOLE.contains(office)) return new Reach(true, Set.of(), Set.of(), "The University");
        if ("ictagent".equals(office)) {
            Map<String, Object> r = jdbc.sql("SELECT global, faculties, departments, words FROM helpdesk.agent_scope_for(:p, :c)")
                    .param("p", actor()).param("c", capability).query().singleRow();
            return new Reach(Boolean.TRUE.equals(r.get("global")), upper(r.get("faculties")), upper(r.get("departments")),
                    r.get("words") == null ? "" : String.valueOf(r.get("words")));
        }
        if (scope.actingDepartmentOffice()) {
            String d = scope.actingDept();
            return new Reach(false, Set.of(), d == null ? Set.of() : Set.of(d.toUpperCase()), d == null ? "" : d);
        }
        if (scope.actingFacultyOffice()) {
            String f = scope.actingFaculty();
            return new Reach(false, f == null ? Set.of() : Set.of(f.toUpperCase()), Set.of(), f == null ? "" : f);
        }
        return new Reach(true, Set.of(), Set.of(), "The University");
    }

    /** the capabilities the acting office holds anywhere (for the screen; each act is still checked on its class) */
    List<String> held() {
        return ALL.stream().filter(c -> !of(c).none()).toList();
    }

    /** the reach of a capability the office must hold somewhere, or the refusal that says who grants it */
    Reach require(String capability) {
        Reach r = of(capability);
        if (r.none()) {
            throw new DomainRuleViolation("ALLOC_CAPABILITY", "Your support posting does not carry " + WORDS.getOrDefault(capability, capability.toLowerCase()) + ".",
                    new DomainRuleViolation.Remedy("Ask the Head of the ICT Support Desk to grant it with your posting.", "Head of ICT Support Desk"));
        }
        return r;
    }

    /** the class's course, department and faculty — or not found */
    Map<String, Object> classOf(UUID offering) {
        return jdbc.sql("""
                SELECT o.id, o.course_code, o.session, o.semester, o.stream, o.lecturer_id, o.second_examiner_id, c.title, c.units, c.level, c.dept_code,
                       d.name AS department, d.faculty_code, f.name AS faculty
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE o.id = :o
                """).param("o", offering).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("class", offering));
    }

    /** the class, held to the capability's reach: a class outside it is refused whatever the address says */
    Map<String, Object> onClass(UUID offering, String capability) {
        Reach r = require(capability);
        Map<String, Object> c = classOf(offering);
        if (!r.covers((String) c.get("faculty_code"), (String) c.get("dept_code"))) {
            throw new DomainRuleViolation("ALLOC_SCOPE", c.get("course_code") + " belongs to " + (c.get("department") == null ? "a department" : c.get("department"))
                    + ", outside your allocation scope (" + (r.words().isBlank() ? "none" : r.words()) + ").",
                    new DomainRuleViolation.Remedy("Escalate it to the Head of the ICT Support Desk or the Director of ICT.", "Head of ICT Support Desk"));
        }
        return c;
    }

    /** the support ticket an act is made on: by its number (or id), one the agent's postings reach; the head and the Director reach
     *  every ticket; none named is none (V408, shared by the desk and the department templates of V478) */
    UUID ticket(String ref) {
        String t = ref == null ? "" : ref.trim();
        if (t.isEmpty()) return null;
        UUID id = jdbc.sql("SELECT id FROM helpdesk.ticket WHERE upper(number) = upper(:n) OR id::text = lower(:n)").param("n", t).query(UUID.class).optional()
                .orElseThrow(() -> new DomainRuleViolation("ALLOC_TICKET", "No support ticket has the number " + t + ".",
                        new DomainRuleViolation.Remedy("Check the ticket number, or leave it blank.", "You")));
        if (agent() && !Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.can_view(:me, :t)").param("me", actor()).param("t", id).query(Boolean.class).single())) {
            throw new DomainRuleViolation("ALLOC_TICKET_SCOPE", "Ticket " + t + " is outside your support scope.",
                    new DomainRuleViolation.Remedy("Work it from a queue you are posted to, or ask the Head of the Support Desk to assign it to you.", "Head of ICT Support Desk"));
        }
        return id;
    }

    /** a filter on a query's department and faculty columns, for lists held to the reach */
    String where(Reach r, String deptColumn, String facultyColumn) {
        if (r.all()) return "TRUE";
        return "(upper(" + deptColumn + ") = ANY (:reach_depts) OR upper(" + facultyColumn + ") = ANY (:reach_facs))";
    }

    static String[] depts(Reach r) {
        return r.departments().toArray(String[]::new);
    }

    static String[] facs(Reach r) {
        return r.faculties().toArray(String[]::new);
    }

    private static Set<String> upper(Object pgArray) {
        Set<String> out = new LinkedHashSet<>();
        try {
            if (pgArray instanceof java.sql.Array a) {
                for (Object o : (Object[]) a.getArray()) if (o != null) out.add(String.valueOf(o).toUpperCase());
            } else if (pgArray instanceof String[] s) {
                for (String o : s) if (o != null) out.add(o.toUpperCase());
            }
        } catch (java.sql.SQLException e) {
            throw new IllegalStateException(e);
        }
        return out;
    }
}
