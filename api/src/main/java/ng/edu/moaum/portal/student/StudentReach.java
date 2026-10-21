package ng.edu.moaum.portal.student;

import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Component;

import ng.edu.moaum.portal.shared.OfficeScope;

/**
 * Whether the acting office may read one student's record — moved here from StudentController (Oct 2026) so the record, the
 * full record and its receipts apply one rule.
 */
@Component
public class StudentReach {

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    StudentReach(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /**
     * V361: one student's record is read within the office's bound, as the register is. A Head of Department, an
     * Examinations Officer, a SIWES Coordinator or a lecturer reads the students of their own department (or programme),
     * and a Dean, a Faculty Officer or a Faculty Examinations Officer those of their faculty — and also a student registered
     * on a course of their own (a lecturer: a course they teach), so a class list still opens every student on it. Every
     * other office that reads the record reads the University's.
     */
    public void check(UUID id) {
        // V603: a College office (the Finance Controller) reads the College's students alone — active, graduated or otherwise
        if (scope.actingCollegeOffice()) {
            String f = jdbc.sql("SELECT p.faculty_code FROM people.student st JOIN ref.programme p ON p.code = st.programme_code WHERE st.id = :id")
                    .param("id", id).query(String.class).optional().orElse(null);
            if (f == null) return;   // an unknown student is answered as not found, not as out of scope
            if (scope.actingCollegeFaculties().stream().noneMatch(f::equalsIgnoreCase)) {
                throw new org.springframework.security.access.AccessDeniedException("This student is outside the College; this office reads the College's students alone.");
            }
            return;
        }
        boolean dept = scope.actingDepartmentOffice();
        boolean fac = scope.actingFacultyOffice();
        if (!dept && !fac) return;
        java.util.Map<String, Object> s = jdbc.sql("""
                SELECT p.code, p.dept_code, p.faculty_code FROM people.student st JOIN ref.programme p ON p.code = st.programme_code WHERE st.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElse(null);
        if (s == null) return;   // an unknown student is answered as not found, not as out of scope
        String prog = scope.actingProgramme();
        boolean within = prog != null ? prog.equalsIgnoreCase(String.valueOf(s.get("code")))
                : scope.within((String) s.get("faculty_code"), (String) s.get("dept_code"), null);
        if (within) return;
        boolean onCourse;
        if (scope.actingLecturer()) {
            onCourse = Boolean.TRUE.equals(jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                                     JOIN catalogue.offering o ON o.id = e.offering_id
                                    WHERE r.student_id = :s AND (o.lecturer_id = :me OR o.second_examiner_id = :me
                                          OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :me)))
                    """).param("s", id).param("me", scope.actorId()).query(Boolean.class).single());
        } else {
            String d = dept ? scope.actingDept() : null;
            String f = fac ? scope.actingFaculty() : null;
            onCourse = (d != null || f != null) && Boolean.TRUE.equals(jdbc.sql("""
                    SELECT EXISTS (SELECT 1 FROM registration.course_registration r JOIN registration.entry e ON e.registration_id = r.id
                                     JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code
                                     JOIN ref.department dd ON dd.code = c.dept_code
                                    WHERE r.student_id = :s AND (c.dept_code = :d OR dd.faculty_code = :f))
                    """).param("s", id).param("d", d, java.sql.Types.VARCHAR).param("f", f, java.sql.Types.VARCHAR).query(Boolean.class).single());
        }
        if (!onCourse) {
            throw new org.springframework.security.access.AccessDeniedException("This student is outside your " + (fac ? "faculty" : "department")
                    + " and on none of its courses; this office reads the records within its own scope.");
        }
    }
}
