package ng.edu.moaum.portal.ref;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class RefRepository {

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    RefRepository(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    Structure structure() {
        // A department office — the Head of Department, the Examinations Officer, a lecturer — works within
        // one department: the ladder is pruned to their department, its faculty and that faculty's college,
        // so the scope bar's Faculty and Department are fixed to their own and only Programme, Level and
        // Course remain to choose. A faculty office — the Dean, the Faculty Officer — is pruned to its
        // faculty. A lecturer is pruned further, to the programmes their courses are offered to, so they see
        // their own students and nobody else's. An office that resolves to nothing sees nothing.
        String hodDept = scope.actingDepartmentOffice() ? (scope.actingDept() == null ? "__none__" : scope.actingDept()) : null;
        String facOnly = scope.actingFacultyOffice() ? (scope.actingFaculty() == null ? "__none__" : scope.actingFaculty()) : null;
        java.util.UUID lecturer = scope.actingLecturer() ? scope.actorId() : null;

        List<Structure.College> colleges = jdbc.sql("""
                SELECT co.code, co.name, co.system, co.url FROM ref.college co
                 WHERE (:dept::text IS NULL OR co.code = (
                         SELECT f.college_code FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code
                          WHERE d.code = :dept))
                   AND (:fac::text IS NULL OR co.code = (SELECT college_code FROM ref.faculty WHERE code = :fac))
                 ORDER BY co.name""")
                .param("dept", hodDept).param("fac", facOnly).query(Structure.College.class).list();
        List<Structure.FacultyRow> faculties = jdbc.sql("""
                SELECT f.code, f.name, f.college_code FROM ref.faculty f
                 WHERE (:dept::text IS NULL OR f.code = (SELECT faculty_code FROM ref.department WHERE code = :dept))
                   AND (:fac::text IS NULL OR f.code = :fac)
                 ORDER BY f.name""")
                .param("dept", hodDept).param("fac", facOnly).query(Structure.FacultyRow.class).list();
        List<Structure.DepartmentRow> departments = jdbc.sql("""
                SELECT code, name, faculty_code FROM ref.department
                 WHERE ended_on IS NULL AND (:dept::text IS NULL OR code = :dept)
                   AND (:fac::text IS NULL OR faculty_code = :fac) ORDER BY name""")
                .param("dept", hodDept).param("fac", facOnly).query(Structure.DepartmentRow.class).list();
        List<Structure.ProgrammeRow> programmes = jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, p.category, p.archived FROM ref.programme p
                 WHERE (:dept::text IS NULL OR p.dept_code = :dept)
                   AND (:fac::text IS NULL OR p.dept_code IN (SELECT code FROM ref.department WHERE faculty_code = :fac))
                   -- a lecturer sees the programmes their courses are offered to; one with no course allocated yet sees the department's
                   AND (:lect::uuid IS NULL
                        OR NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                        WHERE o.lecturer_id = :lect OR o.second_examiner_id = :lect
                                           OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :lect))
                        OR EXISTS (SELECT 1 FROM catalogue.course_offer co
                                     JOIN catalogue.offering o ON o.course_code = co.course_code
                                    WHERE co.programme_code = p.code
                                      AND (o.lecturer_id = :lect OR o.second_examiner_id = :lect
                                           OR EXISTS (SELECT 1 FROM catalogue.offering_teacher t WHERE t.offering_id = o.id AND t.lecturer_id = :lect))))
                 ORDER BY p.name""")
                .param("dept", hodDept).param("fac", facOnly).param("lect", lecturer, java.sql.Types.OTHER).query(Structure.ProgrammeRow.class).list();

        Map<String, List<Structure.Programme>> byDept = new LinkedHashMap<>();
        for (Structure.ProgrammeRow p : programmes) {
            byDept.computeIfAbsent(p.deptCode(), k -> new ArrayList<>())
                    .add(new Structure.Programme(p.code(), p.name(), p.category(), p.archived()));
        }
        Map<String, List<Structure.Department>> byFaculty = new LinkedHashMap<>();
        for (Structure.DepartmentRow d : departments) {
            byFaculty.computeIfAbsent(d.facultyCode(), k -> new ArrayList<>())
                    .add(new Structure.Department(d.code(), d.name(), d.facultyCode(), byDept.getOrDefault(d.code(), List.of())));
        }
        List<Structure.Faculty> out = new ArrayList<>();
        for (Structure.FacultyRow f : faculties) {
            out.add(new Structure.Faculty(f.code(), f.name(), f.collegeCode(), byFaculty.getOrDefault(f.code(), List.of())));
        }
        return new Structure(colleges, out);
    }

    List<Session> sessions() {
        return jdbc.sql("""
                SELECT name, starts_on, ends_on, state, senate_minute, semesters
                  FROM policy.academic_session ORDER BY name DESC
                """).query(Session.class).list();
    }

    List<Course> courses(String deptCode, Integer semester, Integer level) {
        deptCode = scope.scopedDept(deptCode);              // an HOD sees only their department's courses
        return jdbc.sql("""
                SELECT c.code, c.title, c.units, c.semester, c.level, c.dept_code, d.name AS dept_name, c.kind, c.state, c.ended_on
                  FROM catalogue.course c JOIN ref.department d ON d.code = c.dept_code
                 WHERE (:dept::text IS NULL OR c.dept_code = :dept)
                   AND (:sem::int IS NULL OR c.semester = :sem)
                   AND (:level::int IS NULL OR c.level = :level)
                 ORDER BY c.code
                """)
                .param("dept", deptCode).param("sem", semester).param("level", level)
                .query(Course.class).list();
    }

    /** V273: the states with their local governments, names A–Z */
    List<Map<String, Object>> states() {
        return jdbc.sql("""
                SELECT s.code, s.name, coalesce((SELECT json_agg(l.name ORDER BY l.name) FROM ref.lga l WHERE l.state_code = s.code), '[]'::json)::text AS lgas
                  FROM ref.state s ORDER BY s.name
                """).query().listOfRows();
    }

    List<String> countries() {
        return jdbc.sql("SELECT name FROM ref.country ORDER BY home DESC, name").query(String.class).list();
    }
}
