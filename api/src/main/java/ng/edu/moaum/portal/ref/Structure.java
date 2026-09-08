package ng.edu.moaum.portal.ref;

import java.util.List;

/** FACULTY → DEPARTMENT → PROGRAMME, the top of the chain every list in the estate walks. */
public record Structure(List<College> colleges, List<Faculty> faculties) {

    public record College(String code, String name, String system, String url) {
    }

    public record Faculty(String code, String name, String collegeCode, List<Department> departments) {
    }

    public record Department(String code, String name, String facultyCode, List<Programme> programmes) {
    }

    public record Programme(String code, String name, String category, boolean archived) {
    }

    record FacultyRow(String code, String name, String collegeCode) {
    }

    record DepartmentRow(String code, String name, String facultyCode) {
    }

    record ProgrammeRow(String code, String name, String deptCode, String category, boolean archived) {
    }
}
