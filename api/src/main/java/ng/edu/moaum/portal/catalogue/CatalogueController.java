package ng.edu.moaum.portal.catalogue;

import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** A department's course catalogue (V042). */
@RestController
@RequestMapping("/api/v1/catalogue")
class CatalogueController {

    private static final String OWNERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_lecturer','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_records','OFFICE_dvc','OFFICE_vc')";

    /** the Directorate of ICT and Super Administrator, plus the HOD for their own department, upload a structure */
    private static final String UPLOADERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_admin','OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;

    CatalogueController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.json = json;
    }

    public record NewCourse(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 120) String title,
                            @NotNull @Min(0) Integer units, @NotNull Integer semester, @NotNull Integer level,
                            @NotBlank @Size(max = 12) String dept, @Size(max = 20) String kind) {
    }

    public record CourseUpload(@NotBlank @Size(max = 20) String programme, @NotNull List<Map<String, Object>> rows, @Size(max = 10) String curriculum) {
    }

    public record FacultyIn(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 160) String name) {
    }

    public record ProgrammeIn(@NotBlank @Size(max = 6) String code, @NotBlank @Size(max = 160) String name,
                              @NotBlank @Size(max = 160) String faculty, @Size(max = 20) String departmentCode,
                              @Size(max = 160) String department, @Size(max = 20) String category, Integer minScore) {
    }

    public record Rows(@NotNull List<Map<String, Object>> rows) {
    }

    /* ── faculties ── */

    @GetMapping("/faculties")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> faculties() {
        return jdbc.sql("""
                SELECT f.code, f.name,
                       (SELECT count(*) FROM ref.department d WHERE d.faculty_code = f.code) AS departments,
                       (SELECT count(*) FROM ref.programme p WHERE p.faculty_code = f.code AND NOT p.archived) AS programmes
                  FROM ref.faculty f ORDER BY f.name
                """).query().listOfRows();
    }

    @PostMapping("/faculties")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> newFaculty(@Valid @RequestBody FacultyIn body) {
        return jdbc.sql("SELECT code, name FROM ref.upsert_faculty(:c, :n)")
                .param("c", body.code()).param("n", body.name()).query().singleRow();
    }

    @PostMapping("/faculties/import")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> importFaculties(@Valid @RequestBody Rows body) {
        return jdbc.sql("SELECT * FROM ref.import_faculties(:j::jsonb)")
                .param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    /* ── programmes ── */

    @GetMapping("/programmes")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> programmes() {
        return jdbc.sql("""
                SELECT p.code, p.name, p.faculty_code, f.name AS faculty_name, p.dept_code, d.name AS department_name,
                       p.category, p.min_score, p.archived
                  FROM ref.programme p
                  JOIN ref.faculty f ON f.code = p.faculty_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                 ORDER BY f.name, p.name
                """).query().listOfRows();
    }

    @PostMapping("/programmes")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> newProgramme(@Valid @RequestBody ProgrammeIn body) {
        return jdbc.sql("SELECT code, name, faculty_code, dept_code, category, min_score FROM ref.upsert_programme(:c, :n, :f, :dc, :dn, :cat, :ms)")
                .param("c", body.code()).param("n", body.name()).param("f", body.faculty())
                .param("dc", body.departmentCode(), java.sql.Types.VARCHAR).param("dn", body.department(), java.sql.Types.VARCHAR)
                .param("cat", body.category(), java.sql.Types.VARCHAR).param("ms", body.minScore(), java.sql.Types.INTEGER)
                .query().singleRow();
    }

    @PostMapping("/programmes/import")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> importProgrammes(@Valid @RequestBody Rows body) {
        return jdbc.sql("SELECT * FROM ref.import_programmes(:j::jsonb)")
                .param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    public record Archive(@NotNull Boolean archived) {
    }

    /** archive or restore a programme — the safe removal; it keeps its code */
    @PostMapping("/programmes/{code}/archive")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> archiveProgramme(@PathVariable String code, @Valid @RequestBody Archive body) {
        return jdbc.sql("SELECT code, name, archived FROM ref.set_programme_archived(:c, :a)")
                .param("c", code).param("a", body.archived()).query().singleRow();
    }

    /** hard-delete a programme (only when nothing hangs on it) */
    @DeleteMapping("/programmes/{code}")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> deleteProgramme(@PathVariable String code) {
        jdbc.sql("SELECT ref.delete_programme(:c)").param("c", code).query().singleRow();
        return Map.of("code", code.toUpperCase(), "deleted", true);
    }

    /** delete a faculty (only when it holds no programme and no course-bearing department) */
    @DeleteMapping("/faculties/{code}")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> deleteFaculty(@PathVariable String code) {
        jdbc.sql("SELECT ref.delete_faculty(:c)").param("c", code).query().singleRow();
        return Map.of("code", code.toUpperCase(), "deleted", true);
    }

    /** upload a programme's course structure (a CCMAS table): each course is created and offered at its level */
    @PostMapping("/import")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> importCourses(@Valid @RequestBody CourseUpload body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_ROWS", "The structure has no rows to read.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Upload the department's course document.", "Directorate of ICT"));
        }
        return jdbc.sql("SELECT * FROM catalogue.import_courses(:p, :j::jsonb, :curr)")
                .param("p", body.programme()).param("j", json.writeValueAsString(body.rows()))
                .param("curr", body.curriculum() == null || body.curriculum().isBlank() ? null : body.curriculum().trim().toUpperCase(), java.sql.Types.VARCHAR)
                .query().singleRow();
    }

    /** every course a department owns, with the lecturer of its offering in the current session, if any */
    @GetMapping("/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam String dept) {
        return jdbc.sql("""
                WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1)
                SELECT c.code, c.title, c.units, c.semester, c.level, c.kind, c.state, c.ended_on,
                       (SELECT CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
                          FROM catalogue.offering o LEFT JOIN iam.person p ON p.id = o.lecturer_id
                         WHERE o.course_code = c.code AND o.session = (SELECT name FROM cur)
                         ORDER BY o.semester LIMIT 1) AS lecturer,
                       EXISTS (SELECT 1 FROM catalogue.offering o2 WHERE o2.course_code = c.code AND o2.session = (SELECT name FROM cur)) AS offered
                  FROM catalogue.course c
                 WHERE c.dept_code = :dept
                 ORDER BY c.level, c.semester, c.code
                """).param("dept", dept).query().listOfRows();
    }

    /** every course offered to a programme, level by level — the view for the course-upload desk */
    @GetMapping("/offered")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offered(@RequestParam String programme) {
        return jdbc.sql("""
                SELECT c.code, c.title, c.units, co.level, c.semester, c.kind, co.basis,
                       c.lecture_hours, c.practical_hours
                  FROM catalogue.course_offer co
                  JOIN catalogue.course c ON c.code = co.course_code
                 WHERE co.programme_code = :p
                 ORDER BY co.level, c.semester, c.code
                """).param("p", programme).query().listOfRows();
    }

    /** who may register a course: the eligible programme-and-level set, assigned at creation, with how many are registered */
    @GetMapping("/courses/{code}/eligibility")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> eligibility(@PathVariable String code) {
        List<Map<String, Object>> head = jdbc.sql("""
                SELECT c.code, c.title, c.dept_code, d.name AS dept_name, c.units, c.level, c.semester
                  FROM catalogue.course c JOIN ref.department d ON d.code = c.dept_code WHERE c.code = :code
                """).param("code", code).query().listOfRows();
        if (head.isEmpty()) {
            throw new ng.edu.moaum.portal.shared.NotFound("course", code);
        }
        List<Map<String, Object>> offers = jdbc.sql("""
                SELECT co.programme_code, pr.name AS programme, pr.dept_code, d.name AS dept, f.name AS faculty, co.level, co.basis,
                       coalesce((SELECT count(*) FROM registration.entry e
                                   JOIN registration.course_registration r ON r.id = e.registration_id
                                   JOIN catalogue.offering o ON o.id = e.offering_id
                                   JOIN people.student st ON st.id = r.student_id
                                  WHERE o.course_code = co.course_code AND r.status = 'APPROVED'
                                    AND st.programme_code = co.programme_code AND st.current_level = co.level), 0) AS registered
                  FROM catalogue.course_offer co
                  JOIN ref.programme pr ON pr.code = co.programme_code
                  JOIN ref.department d ON d.code = pr.dept_code
                  JOIN ref.faculty f ON f.code = pr.faculty_code
                 WHERE co.course_code = :code
                 ORDER BY co.level, pr.name
                """).param("code", code).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>(head.get(0));
        out.put("offers", offers);
        return out;
    }

    @PostMapping("/courses")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> create(@Valid @RequestBody NewCourse body) {
        String code = jdbc.sql("SELECT catalogue.create_course(:c, :t, :u, :s, :l, :d, :k)")
                .param("c", body.code()).param("t", body.title()).param("u", body.units()).param("s", body.semester())
                .param("l", body.level()).param("d", body.dept()).param("k", body.kind())
                .query(String.class).single();
        return Map.of("code", code, "state", "BOARD");
    }

    @PostMapping("/courses/{code}/end")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> end(@PathVariable String code) {
        jdbc.sql("SELECT catalogue.end_course(:c)").param("c", code).query().singleRow();
        return Map.of("code", code, "state", "ENDED");
    }

    /** how far course-structure upload has got: programmes with a structure loaded vs. still to upload,
     *  the totals, the split by faculty, and the list still pending — for the ICT/management dashboard */
    @GetMapping("/upload-coverage")
    @PreAuthorize("hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_dvc','OFFICE_vc','OFFICE_hod','OFFICE_dean')")
    @Transactional(readOnly = true)
    Map<String, Object> uploadCoverage() {
        Map<String, Object> sum = jdbc.sql("""
                WITH prog AS (SELECT p.code, EXISTS (SELECT 1 FROM catalogue.course_offer o WHERE o.programme_code = p.code) AS uploaded
                                FROM ref.programme p WHERE NOT p.archived)
                SELECT count(*) AS total, count(*) FILTER (WHERE uploaded) AS uploaded FROM prog
                """).query().singleRow();
        long total = ((Number) sum.get("total")).longValue();
        long uploaded = ((Number) sum.get("uploaded")).longValue();
        List<Map<String, Object>> byFaculty = jdbc.sql("""
                SELECT f.name AS faculty, count(*) AS total,
                       count(*) FILTER (WHERE EXISTS (SELECT 1 FROM catalogue.course_offer o WHERE o.programme_code = p.code)) AS uploaded
                  FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT p.archived GROUP BY f.name ORDER BY f.name
                """).query().listOfRows();
        List<Map<String, Object>> pendingList = jdbc.sql("""
                SELECT p.code, p.name, f.name AS faculty
                  FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE NOT p.archived AND NOT EXISTS (SELECT 1 FROM catalogue.course_offer o WHERE o.programme_code = p.code)
                 ORDER BY f.name, p.name
                """).query().listOfRows();
        long courses = jdbc.sql("SELECT count(*) FROM catalogue.course").query(Long.class).single();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("total", total);
        out.put("uploaded", uploaded);
        out.put("pending", total - uploaded);
        out.put("courses", courses);
        out.put("byFaculty", byFaculty);
        out.put("pendingList", pendingList);
        return out;
    }
}
