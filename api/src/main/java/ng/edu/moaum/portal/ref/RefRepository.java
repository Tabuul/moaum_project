package ng.edu.moaum.portal.ref;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.stereotype.Repository;

@Repository
class RefRepository {

    private final JdbcClient jdbc;

    RefRepository(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    Structure structure() {
        List<Structure.College> colleges = jdbc.sql("SELECT code, name, system, url FROM ref.college ORDER BY name")
                .query(Structure.College.class).list();
        List<Structure.FacultyRow> faculties = jdbc.sql("SELECT code, name, college_code FROM ref.faculty ORDER BY name")
                .query(Structure.FacultyRow.class).list();
        List<Structure.DepartmentRow> departments = jdbc.sql(
                "SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name")
                .query(Structure.DepartmentRow.class).list();
        List<Structure.ProgrammeRow> programmes = jdbc.sql(
                "SELECT code, name, dept_code, category, archived FROM ref.programme ORDER BY name")
                .query(Structure.ProgrammeRow.class).list();

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
