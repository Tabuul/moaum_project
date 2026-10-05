package ng.edu.moaum.portal.catalogue;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

/**
 * Who may do what to a course's offerings (V332). A programme's structure is its own department's: its Head binds
 * into it, its Dean may, and the central academic offices may; anyone else offering a course to that programme
 * proposes, and the department decides. A course's own attributes are its owning department's the same way. The
 * rules are the office scope's (V150/V318), answered here rather than thrown, so a desk can show what it may do.
 */
@Component
class OfferAuthority {

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    OfferAuthority(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** true for an office that is neither a department's nor a faculty's: the Academic Office, the Registry, the Directorate */
    boolean central() {
        return !scope.actingDepartmentOffice() && !scope.actingFacultyOffice();
    }

    /** may the acting office bind a course into, or unbind it from, a programme of this department directly? */
    boolean mayBindInto(String programmeDept) {
        return central() || (programmeDept != null && scope.within(null, programmeDept, null));
    }

    /** may the acting office edit, rename, end or offer out a course this department owns? */
    boolean owns(String courseDept) {
        return central() || (courseDept != null && scope.within(null, courseDept, null));
    }

    void assertOwns(String courseDept, String code) {
        if (!owns(courseDept)) {
            throw new DomainRuleViolation("CAT_DEPT", code + " belongs to another department; its own department edits it and offers it out.",
                    new DomainRuleViolation.Remedy("Ask that department's Head, or bind the course into your own programme from the programme's structure.", "Head of Department"));
        }
    }

    /** the acting department, for a proposal's record and for "my proposals"; null for a central office */
    String actingDept() {
        return scope.actingDepartmentOffice() ? scope.actingDept() : null;
    }

    String deptOfProgramme(String prog) {
        return jdbc.sql("SELECT dept_code FROM ref.programme WHERE upper(code) = upper(:p)").param("p", prog == null ? "" : prog.trim())
                .query(String.class).optional().orElseThrow(() -> new NotFound("programme", prog));
    }

    /** one offer of a course to a programme: bound where the office may, proposed to the programme's department where it may not */
    java.util.Map<String, Object> offer(String courseCode, String courseDept, String programme, Integer level, String basisIn, String track, String reason) {
        String prog = programme == null ? "" : programme.trim().toUpperCase();
        String progDept = deptOfProgramme(prog);
        String basis = basisIn == null || basisIn.isBlank() ? (progDept.equalsIgnoreCase(courseDept == null ? "" : courseDept) ? "Core" : "Borrowed") : basisIn.trim();
        if (!java.util.Set.of("Core", "Elective", "Borrowed", "GST").contains(basis)) {
            throw new DomainRuleViolation("CAT_BASIS", "A course is offered to a programme as Core, Elective, Borrowed or GST.",
                    new DomainRuleViolation.Remedy("Choose one of the four.", "Head of Department"));
        }
        String t = track == null || track.isBlank() ? null : track.trim().toUpperCase();
        if (mayBindInto(progDept)) {
            jdbc.sql("SELECT catalogue.bind_offer(:c, :p, :l, :b, :t, 'COURSE')").param("c", courseCode).param("p", prog).param("l", level)
                    .param("b", basis).param("t", t, java.sql.Types.VARCHAR).query().singleRow();
            return java.util.Map.of("programme", prog, "level", level, "basis", basis, "outcome", "BOUND");
        }
        // another department's programme: that department decides; the proposer owns the course or is a central office
        assertOwns(courseDept, courseCode);
        java.util.UUID id = jdbc.sql("SELECT catalogue.propose_offer(:c, :p, :l, :b, :t, :r, :d)").param("c", courseCode).param("p", prog).param("l", level)
                .param("b", basis).param("t", t, java.sql.Types.VARCHAR).param("r", reason == null || reason.isBlank() ? null : reason.trim(), java.sql.Types.VARCHAR)
                .param("d", actingDept(), java.sql.Types.VARCHAR).query(java.util.UUID.class).single();
        return java.util.Map.of("programme", prog, "level", level, "basis", basis, "outcome", "PROPOSED", "proposal", id);
    }

    String deptOfCourse(String code) {
        return jdbc.sql("SELECT dept_code FROM catalogue.course WHERE upper(code) = upper(:c)").param("c", code == null ? "" : code.trim())
                .query(String.class).optional().orElseThrow(() -> new NotFound("course", code));
    }
}
