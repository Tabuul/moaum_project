package ng.edu.moaum.portal.catalogue;

import java.sql.Types;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

/**
 * Who of the School of Postgraduate Studies and the ICT Support Desk may work the one programme structure, and where (V471).
 * The academic offices keep their own rules (OfferAuthority, the department scope): this answers only for
 *
 *  - the Dean and the Secretary of the School (pgschool, pgsecretary): the postgraduate programmes' structures, and the
 *    courses only postgraduate programmes take — never an undergraduate programme's structure, nor a course an undergraduate
 *    programme also takes (its owning department and the Academic Office keep those);
 *  - the Head of the ICT Support Desk (helpdeskhead): every programme and course of the University, as for allocation;
 *  - an ICT Support Agent (ictagent): what the postings grant — VIEW_PROGRAMME_STRUCTURE (every agent in service holds it),
 *    EDIT_COURSES, BIND_COURSES, MANAGE_PREREQUISITES — within the faculties and departments the postings name
 *    (helpdesk.agent_scope_for).
 *
 * Every act is checked here on the server whatever the screen showed; a change made on a ticket is put on its timeline.
 */
@Component
class StructureAccess {

    static final String VIEW = "VIEW_PROGRAMME_STRUCTURE";
    static final String EDIT = "EDIT_COURSES";
    static final String BIND = "BIND_COURSES";
    static final String PREREQ = "MANAGE_PREREQUISITES";
    private static final Map<String, String> WORDS = Map.of(VIEW, "viewing the programme structure", EDIT, "editing courses",
            BIND, "binding courses into programmes", PREREQ, "managing prerequisites");

    private static final Set<String> PG = Set.of("pgschool", "pgsecretary");
    private static final Set<String> SUPPORT = Set.of("ictagent", "helpdeskhead");

    private final JdbcClient jdbc;

    StructureAccess(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    private static UUID actor() {
        return AuditContextHolder.current().map(c -> c.actorId()).orElse(null);
    }

    /** the School of Postgraduate Studies' offices */
    static boolean pg() {
        return PG.contains(office());
    }

    /** the offices this class answers for; the academic offices are OfferAuthority's */
    static boolean special() {
        return PG.contains(office()) || SUPPORT.contains(office());
    }

    /** the University, or the faculties and departments an agent's postings carrying the capability name */
    record Reach(boolean all, Set<String> faculties, Set<String> departments, String words) {
        boolean none() {
            return !all && faculties.isEmpty() && departments.isEmpty();
        }

        boolean covers(String faculty, String dept) {
            return all || (faculty != null && faculties.contains(faculty.toUpperCase())) || (dept != null && departments.contains(dept.toUpperCase()));
        }
    }

    private Reach reach(String capability) {
        if (!"ictagent".equals(office())) return new Reach(true, Set.of(), Set.of(), "The University");
        Map<String, Object> r = jdbc.sql("SELECT global, faculties, departments, words FROM helpdesk.agent_scope_for(:p, :c)")
                .param("p", actor()).param("c", capability).query().singleRow();
        return new Reach(Boolean.TRUE.equals(r.get("global")), upper(r.get("faculties")), upper(r.get("departments")),
                r.get("words") == null ? "" : String.valueOf(r.get("words")));
    }

    private Reach require(String capability) {
        Reach r = reach(capability);
        if (r.none()) {
            throw new DomainRuleViolation("STRUCTURE_CAPABILITY", "Your support posting does not carry " + WORDS.getOrDefault(capability, capability.toLowerCase()) + ".",
                    new DomainRuleViolation.Remedy("Ask the Head of the ICT Support Desk to grant it with your posting.", "Head of ICT Support Desk"));
        }
        return r;
    }

    /** the capabilities the acting office holds anywhere, for the screen (each act is still checked where it lands) */
    List<String> held() {
        if (!special()) return List.of();
        if (pg() || "helpdeskhead".equals(office())) return List.of(VIEW, EDIT, BIND, PREREQ);
        return List.of(VIEW, EDIT, BIND, PREREQ).stream().filter(c -> !reach(c).none()).toList();
    }

    /** an agent reads the structure only with VIEW_PROGRAMME_STRUCTURE (every agent in service holds it) */
    void requireView() {
        if ("ictagent".equals(office())) require(VIEW);
    }

    private Map<String, Object> programme(String code) {
        return jdbc.sql("SELECT p.code, p.name, p.category, p.dept_code, coalesce(p.faculty_code, d.faculty_code) AS faculty_code FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = :p")
                .param("p", code).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("programme", code));
    }

    private Map<String, Object> course(String code) {
        return jdbc.sql("""
                SELECT c.code, c.title, c.level, c.dept_code, d.faculty_code,
                       EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                                WHERE co.course_code = c.code AND p.category IS DISTINCT FROM 'POST GRADUATE') AS undergraduate,
                       EXISTS (SELECT 1 FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code
                                WHERE co.course_code = c.code AND p.category = 'POST GRADUATE') AS postgraduate
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.code = :c
                """).param("c", code).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("course", code));
    }

    /* ── the rules of a binding, for every office ── */

    /** the bases an undergraduate programme takes a course on, and a postgraduate programme's (V389: deficiency and research) */
    static final List<String> UG_BASES = List.of("Core", "Elective", "Borrowed", "GST");
    static final List<String> PG_BASES = List.of("Core", "Elective", "Borrowed", "Deficiency", "Research");

    boolean postgraduate(String programme) {
        return "POST GRADUATE".equals(programme(programme).get("category"));
    }

    /** the basis a course is bound on, checked against the programme's kind; none given is the default */
    String basis(String programme, String in, String dflt) {
        String b = in == null || in.isBlank() ? dflt : in.trim();
        boolean pgp = postgraduate(programme);
        List<String> allowed = pgp ? PG_BASES : UG_BASES;
        for (String a : allowed) if (a.equalsIgnoreCase(b)) return a;
        throw new DomainRuleViolation("CAT_BASIS", pgp
                ? "A postgraduate programme takes a course as Core, Elective, Borrowed, Deficiency or Research."
                : "A course is offered to a programme as Core, Elective, Borrowed or GST.",
                new DomainRuleViolation.Remedy("Choose one of " + String.join(", ", allowed) + ".", pgp ? "School of Postgraduate Studies" : "Head of Department"));
    }

    /** the level a course is bound at: a postgraduate programme's 700 (PGD), 800 (Masters) or 900 (Doctorate); an
     *  undergraduate programme's 100 to 600 */
    void assertLevel(String programme, int level) {
        if (postgraduate(programme)) {
            if (level != 700 && level != 800 && level != 900) {
                throw new DomainRuleViolation("CAT_PG_LEVEL", "A postgraduate programme takes its courses at 700, 800 or 900 level.",
                        new DomainRuleViolation.Remedy("Choose 700 (postgraduate diploma), 800 (masters) or 900 (doctorate).", "School of Postgraduate Studies"));
            }
        } else if (level < 100 || level > 600) {
            throw new DomainRuleViolation("CAT_UG_LEVEL", "An undergraduate programme takes its courses at 100 to 600 level.",
                    new DomainRuleViolation.Remedy("Bind the course at one of the programme's levels; a 700 to 900 level is a postgraduate programme's.", "Head of Department"));
        }
    }

    /** the same as a yes or no, for a screen's buttons */
    boolean mayProgramme(String code) {
        if (!special()) return false;
        Map<String, Object> p = programme(code);
        if (pg()) return "POST GRADUATE".equals(p.get("category"));
        return reach(BIND).covers((String) p.get("faculty_code"), (String) p.get("dept_code"));
    }

    /** a programme's structure may be changed by the acting office (bind, unbind, the programme's units) */
    void assertProgramme(String code) {
        if (!special()) return;
        Map<String, Object> p = programme(code);
        if (pg()) {
            if (!"POST GRADUATE".equals(p.get("category"))) {
                throw new DomainRuleViolation("STRUCTURE_PG_ONLY", p.get("name") + " is not a postgraduate programme; the School of Postgraduate Studies keeps the postgraduate programmes' structures.",
                        new DomainRuleViolation.Remedy("Its department and the Academic Office keep an undergraduate programme's structure.", "Head of Department"));
            }
            return;
        }
        Reach r = require(BIND);
        if (!r.covers((String) p.get("faculty_code"), (String) p.get("dept_code"))) {
            throw new DomainRuleViolation("STRUCTURE_SCOPE", p.get("name") + " is outside your support scope (" + (r.words().isBlank() ? "none" : r.words()) + ").",
                    new DomainRuleViolation.Remedy("Escalate it to the Head of the ICT Support Desk or the Director of ICT.", "Head of ICT Support Desk"));
        }
    }

    /** may the acting office change the course itself (its title, units, semester, level, code; end or restore it)? */
    boolean mayCourse(String code, String capability) {
        if (!special()) return false;
        Map<String, Object> c = course(code);
        if (pg()) return !Boolean.TRUE.equals(c.get("undergraduate")) && (Boolean.TRUE.equals(c.get("postgraduate")) || ((Number) c.get("level")).intValue() >= 700);
        Reach r = reach(capability);
        return r.covers((String) c.get("faculty_code"), (String) c.get("dept_code"));
    }

    void assertCourse(String code, String capability) {
        if (!special()) return;
        if (mayCourse(code, capability)) return;
        if (pg()) {
            throw new DomainRuleViolation("STRUCTURE_PG_ONLY", code + " is also taken by an undergraduate programme (or is not a postgraduate course); its own department and the Academic Office change it.",
                    new DomainRuleViolation.Remedy("Bind it into a postgraduate programme as it is, or ask its department.", "Head of Department"));
        }
        Reach r = require(capability);
        throw new DomainRuleViolation("STRUCTURE_SCOPE", code + " belongs to a department outside your support scope (" + (r.words().isBlank() ? "none" : r.words()) + ").",
                new DomainRuleViolation.Remedy("Escalate it to the Head of the ICT Support Desk or the Director of ICT.", "Head of ICT Support Desk"));
    }

    /** an edit by the School keeps the course a postgraduate one (700 to 900 level) */
    void assertEditLevel(int level) {
        if (pg() && level < 700) {
            throw new DomainRuleViolation("STRUCTURE_PG_ONLY", "The School of Postgraduate Studies keeps its courses at 700, 800 or 900 level.",
                    new DomainRuleViolation.Remedy("Keep the postgraduate level; an undergraduate course is its department's.", "Head of Department"));
        }
    }

    /** a new course: the PG offices create postgraduate courses (700 to 900 level), an agent with EDIT_COURSES within its scope */
    void assertNewCourse(String dept, int level, List<String> programmes) {
        if (!special()) return;
        if (pg()) {
            if (level < 700) {
                throw new DomainRuleViolation("STRUCTURE_PG_ONLY", "The School of Postgraduate Studies creates postgraduate courses, at 700, 800 or 900 level.",
                        new DomainRuleViolation.Remedy("Give the course its postgraduate level; an undergraduate course is its department's.", "Head of Department"));
            }
            for (String p : programmes) assertProgramme(p);
            return;
        }
        Reach r = require(EDIT);
        String faculty = jdbc.sql("SELECT faculty_code FROM ref.department WHERE code = :d").param("d", dept).query(String.class).optional().orElse(null);
        if (!r.covers(faculty, dept)) {
            throw new DomainRuleViolation("STRUCTURE_SCOPE", "That department is outside your support scope (" + (r.words().isBlank() ? "none" : r.words()) + ").",
                    new DomainRuleViolation.Remedy("Escalate it to the Head of the ICT Support Desk or the Director of ICT.", "Head of ICT Support Desk"));
        }
    }

    /** the offices that work tickets: the support desk, and the Directorate of ICT that heads it */
    private static final Set<String> TICKET_OFFICES = Set.of("ictagent", "helpdeskhead", "ict", "admin", "super");

    /** may the acting office link a change to a support ticket? */
    static boolean ticketOffice() {
        return TICKET_OFFICES.contains(office());
    }

    /** the ticket a support change is made on: its number (ICT-2026-001245) or id; none given is none. An agent links a
     *  change only to a ticket their postings let them see (helpdesk.can_view, as the desk itself checks) */
    UUID ticket(String ref) {
        if (ref == null || ref.isBlank()) return null;
        String t = ref.trim();
        if (!TICKET_OFFICES.contains(office())) {
            throw new DomainRuleViolation("STRUCTURE_TICKET", "A change is linked to a support ticket on the ICT Support Desk.",
                    new DomainRuleViolation.Remedy("Make the change without a ticket; give the reason instead.", "Head of ICT Support Desk"));
        }
        UUID id = jdbc.sql("SELECT id FROM helpdesk.ticket WHERE upper(number) = upper(:t) OR id::text = :t").param("t", t)
                .query(UUID.class).optional().orElseThrow(() -> new NotFound("ticket", t));
        if ("ictagent".equals(office()) && !Boolean.TRUE.equals(jdbc.sql("SELECT helpdesk.can_view(:p, :t)").param("p", actor()).param("t", id)
                .query(Boolean.class).single())) {
            throw new org.springframework.security.access.AccessDeniedException("That ticket is outside your support scope.");
        }
        return id;
    }

    /** the change on the ticket's timeline, with the request's reason */
    void note(UUID ticket, String summary) {
        if (ticket == null) return;
        String reason = AuditContextHolder.current().map(c -> c.reason()).orElse(null);
        jdbc.sql("SELECT helpdesk.note_structure(:t, :s, :r)").param("t", ticket, Types.OTHER).param("s", summary)
                .param("r", reason, Types.VARCHAR).query().listOfRows();
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
