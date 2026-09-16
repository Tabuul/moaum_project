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
        // A Head of Department works within one department. When the request is an HOD's,
        // the ladder is pruned to their department, its faculty and that faculty's college,
        // so the scope bar's Faculty and Department are fixed to their own and only
        // Programme, Level and Course remain to choose.
        String hodDept = scope.actingHod() ? scope.actingHodDept() : null;

        List<Structure.College> colleges = jdbc.sql("""
                SELECT co.code, co.name, co.system, co.url FROM ref.college co
                 WHERE (:dept::text IS NULL OR co.code = (
                         SELECT f.college_code FROM ref.department d JOIN ref.faculty f ON f.code = d.faculty_code
                          WHERE d.code = :dept))
                 ORDER BY co.name""")
                .param("dept", hodDept).query(Structure.College.class).list();
        List<Structure.FacultyRow> faculties = jdbc.sql("""
                SELECT f.code, f.name, f.college_code FROM ref.faculty f
                 WHERE (:dept::text IS NULL OR f.code = (SELECT faculty_code FROM ref.department WHERE code = :dept))
                 ORDER BY f.name""")
                .param("dept", hodDept).query(Structure.FacultyRow.class).list();
        List<Structure.DepartmentRow> departments = jdbc.sql("""
                SELECT code, name, faculty_code FROM ref.department
                 WHERE ended_on IS NULL AND (:dept::text IS NULL OR code = :dept) ORDER BY name""")
                .param("dept", hodDept).query(Structure.DepartmentRow.class).list();
        List<Structure.ProgrammeRow> programmes = jdbc.sql("""
                SELECT code, name, dept_code, category, archived FROM ref.programme
                 WHERE (:dept::text IS NULL OR dept_code = :dept) ORDER BY name""")
                .param("dept", hodDept).query(Structure.ProgrammeRow.class).list();

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
}
