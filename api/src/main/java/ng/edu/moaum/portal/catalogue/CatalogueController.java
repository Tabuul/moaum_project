package ng.edu.moaum.portal.catalogue;

import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
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

    /** the Director of ICT alone creates, uploads, archives or removes faculties, departments, programmes and course structures */
    private static final String UPLOADERS = "hasAuthority('OFFICE_ict')";
    /** opening registration for a session is not a structure upload: the offices that could before still can */
    private static final String OPENERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_admin','OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;

    CatalogueController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, ng.edu.moaum.portal.shared.OfficeScope scope) {
        this.jdbc = jdbc;
        this.json = json;
        this.scope = scope;
    }

    /** the department an HOD request is confined to, or null for any other office (no confinement) */
    private String hodDept() {
        return scope.actingHod() ? scope.scopedDept(null) : null;
    }

    /** a course/department write is refused when an HOD reaches outside their own department */
    private void assertHodOwns(String dept) {
        String hd = hodDept();
        if (hd != null && !hd.equalsIgnoreCase(dept == null ? "" : dept)) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_DEPT",
                    "A Head of Department manages the catalogue of their own department only.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy(
                            "Work within your department; another department manages its own courses.", "Head of Department"));
        }
    }

    public record NewCourse(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 120) String title,
                            @NotNull @Min(0) Integer units, @NotNull Integer semester, @NotNull Integer level,
                            @NotBlank @Size(max = 12) String dept, @Size(max = 20) String kind) {
    }

    public record CourseUpload(@NotBlank @Size(max = 20) String programme, @NotNull List<Map<String, Object>> rows, @Size(max = 12) String curriculum) {
    }

    public record FacultyIn(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 160) String name) {
    }

    public record ProgrammeIn(@NotBlank @Size(max = 6) String code, @NotBlank @Size(max = 160) String name,
                              @NotBlank @Size(max = 160) String faculty, @Size(max = 20) String departmentCode,
                              @Size(max = 160) String department, @Size(max = 20) String category, Integer minScore) {
    }

    public record DepartmentIn(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 160) String name,
                               @NotBlank @Size(max = 160) String faculty) {
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
                  FROM ref.faculty f
                 WHERE (:hod::text IS NULL OR f.code = (SELECT faculty_code FROM ref.department WHERE code = :hod))
                 ORDER BY f.name
                """).param("hod", hodDept()).query().listOfRows();
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

    /* ── departments ── */

    @GetMapping("/departments")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> departments() {
        return jdbc.sql("""
                SELECT d.code, d.name, d.faculty_code, f.name AS faculty_name,
                       (SELECT count(*) FROM ref.programme p WHERE p.dept_code = d.code AND NOT p.archived) AS programmes,
                       (SELECT count(*) FROM catalogue.course c WHERE c.dept_code = d.code) AS courses
                  FROM ref.department d
                  JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE (:hod::text IS NULL OR d.code = :hod)
                 ORDER BY f.name, d.name
                """).param("hod", hodDept()).query().listOfRows();
    }

    @PostMapping("/departments")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> newDepartment(@Valid @RequestBody DepartmentIn body) {
        assertHodOwns(body.code());                         // an HOD cannot create or rename another department
        return jdbc.sql("SELECT code, name, faculty_code FROM ref.upsert_department(:c, :n, :f)")
                .param("c", body.code()).param("n", body.name()).param("f", body.faculty()).query().singleRow();
    }

    @PostMapping("/departments/import")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> importDepartments(@Valid @RequestBody Rows body) {
        return jdbc.sql("SELECT * FROM ref.import_departments(:j::jsonb)")
                .param("j", json.writeValueAsString(body.rows())).query().singleRow();
    }

    /** delete a department (only when it holds no programme and no course) */
    @DeleteMapping("/departments/{code}")
    @PreAuthorize(UPLOADERS)
    @Transactional
    Map<String, Object> deleteDepartment(@PathVariable String code) {
        jdbc.sql("SELECT ref.delete_department(:c)").param("c", code).query().singleRow();
        return Map.of("code", code.toUpperCase(), "deleted", true);
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
                 WHERE (:hod::text IS NULL OR p.dept_code = :hod)
                 ORDER BY f.name, p.name
                """).param("hod", hodDept()).query().listOfRows();
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

    /** open course registration for a session: create an offering for every offered course of that
     *  semester, so students see the real programme/level courses (not leftover demo offerings) */
    @PostMapping("/open-registration")
    @PreAuthorize(OPENERS)
    @Transactional
    Map<String, Object> openRegistration(@RequestParam String session, @RequestParam int semester) {
        Integer n = jdbc.sql("SELECT registration.open_course_registration(:s, :sem)")
                .param("s", session).param("sem", semester).query(Integer.class).single();
        return Map.of("opened", n, "session", session, "semester", semester);
    }

    /** every course a department owns, with the lecturer of its offering in the current session, if any */
    @GetMapping("/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam String dept) {
        dept = scope.scopedDept(dept);                      // an HOD sees only their own department's courses
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH cur AS (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1)
                SELECT c.code, c.title, c.units, c.semester, c.level, c.kind, c.state, c.ended_on, c.curriculum, c.ca_max,
                       (SELECT CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
                          FROM catalogue.offering o LEFT JOIN iam.person p ON p.id = o.lecturer_id
                         WHERE o.course_code = c.code AND o.session = (SELECT name FROM cur)
                         ORDER BY o.semester LIMIT 1) AS lecturer,
                       EXISTS (SELECT 1 FROM catalogue.offering o2 WHERE o2.course_code = c.code AND o2.session = (SELECT name FROM cur)) AS offered,
                       coalesce((SELECT jsonb_agg(DISTINCT co.programme_code) FROM catalogue.course_offer co WHERE co.course_code = c.code), '[]'::jsonb) AS programmes,
                       coalesce((SELECT jsonb_agg(jsonb_build_object('programme_code', co.programme_code, 'programme', p.name, 'level', co.level, 'basis', co.basis, 'track', co.track) ORDER BY p.name, co.level)
                                   FROM catalogue.course_offer co JOIN ref.programme p ON p.code = co.programme_code WHERE co.course_code = c.code), '[]'::jsonb) AS bindings
                  FROM catalogue.course c
                 WHERE c.dept_code = :dept
                 ORDER BY c.level, c.semester, c.code
                """).param("dept", dept).query().listOfRows();
        // programmes and bindings come back as jsonb strings over JDBC; parse them to real values
        for (Map<String, Object> row : rows) {
            Object pr = row.get("programmes");
            row.put("programmes", json.readValue(pr == null ? "[]" : pr.toString(),
                    new tools.jackson.core.type.TypeReference<List<String>>() { }));
            Object bd = row.get("bindings");
            row.put("bindings", json.readValue(bd == null ? "[]" : bd.toString(),
                    new tools.jackson.core.type.TypeReference<List<Map<String, Object>>>() { }));
        }
        return rows;
    }

    public record CurriculumIn(@Size(max = 12) String curriculum) {
    }

    /** a curriculum names a track — BMAS, CCMAS_BSU, CCMAS_MOAU (V235) — or a bare framework, CCMAS or BMAS */
    private static final java.util.Set<String> CURRICULA = java.util.Set.of("CCMAS", "BMAS", "CCMAS_BSU", "CCMAS_MOAU");

    private static String cleanCurriculum(String v) {
        String c = v == null || v.isBlank() ? null : v.trim().toUpperCase().replace('-', '_').replace(' ', '_');
        if (c != null && !CURRICULA.contains(c)) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_CURRICULUM", "A curriculum is BMAS, CCMAS (BSU cohort), CCMAS (MOAU cohorts) or CCMAS for any cohort.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose one of the tracks, or clear it.", "Head of Department"));
        }
        return c;
    }

    /* ── a programme's structure: what it offers at each level, and the binding of a course into it (V013 course_offer, V235 track) ── */

    private String programmeDept(String prog) {
        return jdbc.sql("SELECT dept_code FROM ref.programme WHERE upper(code) = upper(:p)").param("p", prog)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("programme", prog));
    }

    /** every course a programme offers, by level and semester, with the level's unit limits */
    @GetMapping("/structure")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> structure(@RequestParam String prog) {
        String p = prog.trim().toUpperCase();
        scope.bound(null, null, p);                        // a department office reads its own programmes only
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT co.level, c.semester, c.code, c.title, c.units, c.kind, c.state, c.dept_code, d.name AS dept_name, co.basis, co.track, c.ca_max
                  FROM catalogue.course_offer co
                  JOIN catalogue.course c ON c.code = co.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE co.programme_code = :p
                 ORDER BY co.level, c.semester, (co.basis = 'GST') DESC, (co.basis IN ('Core','GST')) DESC, c.code
                """).param("p", p).query().listOfRows();
        List<Map<String, Object>> limits = jdbc.sql("SELECT level, min_units, max_units FROM policy.level_limit ORDER BY level").query().listOfRows();
        Map<String, Object> programme = jdbc.sql("""
                SELECT p.code, p.name, p.dept_code, d.name AS dept_name, p.faculty_code FROM ref.programme p LEFT JOIN ref.department d ON d.code = p.dept_code WHERE p.code = :p
                """).param("p", p).query().listOfRows().stream().findFirst().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("programme", prog));
        List<Map<String, Object>> tracks = jdbc.sql("SELECT code, name FROM policy.curriculum_track ORDER BY code").query().listOfRows();
        return Map.of("programme", programme, "rows", rows, "limits", limits, "tracks", tracks);
    }

    public record BindIn(@NotBlank @Size(max = 12) String programme, @NotBlank @Size(max = 24) String course,
                         @NotNull @Min(100) @Max(600) Integer level, @Size(max = 12) String basis, @Size(max = 12) String track) {
    }

    /** bind a course into a programme's structure at a level, on a basis, for a track (or every track) */
    @PostMapping("/structure/bind")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> bind(@Valid @RequestBody BindIn body) {
        String p = body.programme().trim().toUpperCase();
        String c = body.course().trim().toUpperCase();
        assertHodOwns(programmeDept(p));                    // the programme's department binds into its structure
        String basis = body.basis() == null || body.basis().isBlank() ? "Core" : body.basis().trim();
        if (!List.of("Core", "Elective", "Borrowed", "GST").contains(basis)) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_BASIS", "A course is offered to a programme as Core, Elective, Borrowed or GST.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose one of the four.", "Head of Department"));
        }
        String track = body.track() == null || body.track().isBlank() ? null : body.track().trim().toUpperCase();
        Map<String, Object> course = jdbc.sql("SELECT code, state, dept_code FROM catalogue.course WHERE code = :c").param("c", c)
                .query().listOfRows().stream().findFirst().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", c));
        if ("ENDED".equals(course.get("state"))) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_ENDED", c + " has ended; an ended course is not offered to a programme.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Restore the course on its department's desk first, or bind another.", "Head of Department"));
        }
        jdbc.sql("""
                INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, track) VALUES (:c, :p, :l, :b, :t)
                ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis, track = EXCLUDED.track
                """).param("c", c).param("p", p).param("l", body.level()).param("b", basis).param("t", track, java.sql.Types.VARCHAR).update();
        return Map.of("programme", p, "course", c, "level", body.level(), "basis", basis, "track", track == null ? "" : track);
    }

    /** unbind a course from a programme at a level — refused while a student of that programme and level is registered on it this session */
    @DeleteMapping("/structure/bind")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> unbind(@RequestParam String programme, @RequestParam String course, @RequestParam int level) {
        String p = programme.trim().toUpperCase();
        String c = course.trim().toUpperCase();
        assertHodOwns(programmeDept(p));
        long live = jdbc.sql("""
                SELECT count(*) FROM registration.entry e
                  JOIN registration.course_registration r ON r.id = e.registration_id
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN people.student st ON st.id = r.student_id
                 WHERE o.course_code = :c AND st.programme_code = :p AND r.level = :l
                   AND e.status IN ('REGISTERED','APPROVED') AND r.status <> 'RETURNED'
                   AND r.session = (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1)
                """).param("c", c).param("p", p).param("l", level).query(Long.class).single();
        if (live > 0) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_BOUND_IN_USE",
                    live + " student" + (live == 1 ? "" : "s") + " of " + p + " at " + level + " level " + (live == 1 ? "is" : "are") + " registered on " + c + " this session; the binding stays while they are.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Unbind it after the session, or have the registrations amended first.", "Head of Department"));
        }
        int n = jdbc.sql("DELETE FROM catalogue.course_offer WHERE course_code = :c AND programme_code = :p AND level = :l")
                .param("c", c).param("p", p).param("l", level).update();
        if (n == 0) throw new ng.edu.moaum.portal.shared.NotFound("binding", c + " → " + p + " at " + level);
        return Map.of("programme", p, "course", c, "level", level, "removed", n);
    }

    /** a course anywhere in the University, by code or title, for the structure's picker */
    @GetMapping("/courses/search")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> searchCourses(@RequestParam String q) {
        String needle = "%" + q.trim().toLowerCase() + "%";
        if (q.trim().length() < 2) return List.of();
        return jdbc.sql("""
                SELECT c.code, c.title, c.units, c.semester, c.level, c.kind, c.state, c.dept_code, d.name AS dept_name
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.state <> 'ENDED' AND (lower(c.code) LIKE :q OR lower(c.title) LIKE :q)
                 ORDER BY (lower(c.code) LIKE :q) DESC, c.code
                 LIMIT 25
                """).param("q", needle).query().listOfRows();
    }

    /** tag one course's curriculum (CCMAS / BMAS, or blank to clear) so registration shows it to the
     *  matching cohort only (V116/V160) */
    @PostMapping("/courses/{code}/curriculum")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> setCurriculum(@PathVariable String code, @RequestBody CurriculumIn body) {
        String curr = cleanCurriculum(body.curriculum());
        if (curr != null && curr.startsWith("CCMAS_")) curr = "CCMAS";   // the course carries the framework; the structure row carries the track
        String c = code.trim().toUpperCase();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", c)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", code));
        assertHodOwns(dept);                                // an HOD tags only their own department's courses
        jdbc.sql("UPDATE catalogue.course SET curriculum = :curr WHERE code = :c")
                .param("curr", curr, java.sql.Types.VARCHAR).param("c", c).update();
        return Map.of("code", c, "curriculum", curr == null ? "" : curr);
    }

    public record SplitIn(@NotNull @Min(0) @Max(100) Integer caMax) {
    }

    /** how one course's hundred marks split between continuous assessment and the examination (V239):
     *  the CA share; the examination is the rest */
    @PostMapping("/courses/{code}/split")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> setSplit(@PathVariable String code, @Valid @RequestBody SplitIn body) {
        String c = code.trim().toUpperCase();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", c)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", code));
        assertHodOwns(dept);
        jdbc.sql("UPDATE catalogue.course SET ca_max = :m WHERE code = :c").param("m", body.caMax()).param("c", c).update();
        return Map.of("code", c, "caMax", body.caMax(), "examMax", 100 - body.caMax());
    }

    /** the same split for a whole department's live courses, optionally one level */
    @PostMapping("/split/bulk")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> bulkSplit(@RequestParam String dept, @RequestParam int caMax, @RequestParam(required = false) Integer level) {
        if (caMax < 0 || caMax > 100) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_SPLIT", "The CA share is between 0 and 100 of the hundred marks.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose 40/60 or 30/70.", "Head of Department"));
        }
        String d = scope.scopedDept(dept);
        int n = jdbc.sql("""
                UPDATE catalogue.course SET ca_max = :m
                 WHERE dept_code = :d AND state <> 'ENDED' AND code NOT LIKE 'DMO %'
                   AND (:lvl::int IS NULL OR level = :lvl)
                """).param("m", caMax).param("d", d).param("lvl", level, java.sql.Types.INTEGER).update();
        return Map.of("dept", d, "caMax", caMax, "examMax", 100 - caMax, "updated", n);
    }

    /** tag a whole department's live courses (optionally one level) with a curriculum in one action —
     *  e.g. set every 400 level course to BMAS for the outgoing cohort */
    @PostMapping("/curriculum/bulk")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> bulkCurriculum(@RequestParam String dept, @RequestParam String curriculum, @RequestParam(required = false) Integer level) {
        String curr = cleanCurriculum(curriculum);
        String d = scope.scopedDept(dept);
        int n = jdbc.sql("""
                UPDATE catalogue.course SET curriculum = :curr
                 WHERE dept_code = :d AND state <> 'ENDED' AND code NOT LIKE 'DMO %'
                   AND (:lvl::int IS NULL OR level = :lvl)
                """).param("curr", curr, java.sql.Types.VARCHAR).param("d", d).param("lvl", level, java.sql.Types.INTEGER).update();
        return Map.of("dept", d, "curriculum", curr == null ? "" : curr, "updated", n);
    }

    /* the same course uploaded under two codes (a clean 'CMP 311' and a messy 'BSU-COS 311' or a
       combined 'CSC 309/CMP 441') shows twice on registration. Group a department's live courses by
       level, semester and title; the cleanest code is the keeper, the rest are duplicates. */
    private static final String DUPLICATES_CTE = """
            WITH offered AS (
                SELECT c.code, c.title, c.level, c.semester, coalesce(c.curriculum, '') AS curr,
                       lower(regexp_replace(btrim(c.title), '\\s+', ' ', 'g')) AS norm_title,
                       (c.code LIKE '%/%' OR c.code LIKE '%-%')::int AS messy,
                       (c.code ~ '^[A-Z]{2,4} [0-9]{3}$')::int AS clean
                  FROM catalogue.course c
                 WHERE c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %' AND c.dept_code = :dept),
            grp AS (
                -- partition by curriculum too: a BMAS course and its CCMAS counterpart are two
                -- curricula, not a duplicate to end (V116/V160), so they never group together
                SELECT o.*,
                       count(*) OVER (PARTITION BY level, semester, norm_title, curr) AS n,
                       row_number() OVER (PARTITION BY level, semester, norm_title, curr
                                          ORDER BY messy ASC, clean DESC, length(code) ASC, code ASC) AS rnk
                  FROM offered o)
            """;

    /** the duplicate courses in a department: each group's keeper and the codes that would be ended */
    @GetMapping("/duplicates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> duplicates(@RequestParam String dept) {
        return jdbc.sql(DUPLICATES_CTE + """
                SELECT level, semester, title, code, (rnk = 1) AS keeper
                  FROM grp WHERE n > 1
                 ORDER BY level, semester, norm_title, rnk
                """).param("dept", scope.scopedDept(dept)).query().listOfRows();
    }

    /** end the duplicate courses in a department, keeping the cleanest code in each group */
    @PostMapping("/duplicates/end")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> endDuplicates(@RequestParam String dept) {
        int ended = jdbc.sql(DUPLICATES_CTE + """
                UPDATE catalogue.course c SET state = 'ENDED', ended_on = current_date
                  FROM grp
                 WHERE c.code = grp.code AND grp.n > 1 AND grp.rnk > 1 AND c.state <> 'ENDED'
                """).param("dept", scope.scopedDept(dept)).update();
        return Map.of("ended", ended, "dept", scope.scopedDept(dept));
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

    /** the whole uploaded catalogue — every course offered to every programme — for a download */
    @GetMapping("/catalogue-export")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> catalogueExport() {
        return jdbc.sql("""
                SELECT f.name AS faculty, pr.code AS programme_code, pr.name AS programme,
                       d.name AS department, co.level, c.semester, c.code, c.title, c.units,
                       c.kind, co.basis, c.curriculum
                  FROM catalogue.course_offer co
                  JOIN catalogue.course c ON c.code = co.course_code
                  JOIN ref.programme pr ON pr.code = co.programme_code
                  JOIN ref.faculty f ON f.code = pr.faculty_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 ORDER BY f.name, pr.name, co.level, c.semester, c.code
                """).query().listOfRows();
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
        assertHodOwns(body.dept());                         // an HOD creates courses in their own department only
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

    /** create the current-session offering for a live course, so it appears in registration at once.
     *  student_menu lists a course only when a catalogue.offering exists for the session and the
     *  course's semester; a course made live (or restored) after registration was opened has none. */
    private void ensureCurrentOffering(String code) {
        jdbc.sql("""
                INSERT INTO catalogue.offering (id, course_code, session, semester)
                SELECT gen_random_uuid(), c.code, cur.name, c.semester
                  FROM catalogue.course c
                  CROSS JOIN (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1) cur
                 WHERE c.code = :c AND c.state <> 'ENDED'
                   AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
                   AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                    WHERE o.course_code = c.code AND o.session = cur.name AND o.semester = c.semester)
                """).param("c", code).update();
    }

    /** reverse an end: an ended course returns to LIVE and re-enters next session's registration */
    @PostMapping("/courses/{code}/restore")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> restore(@PathVariable String code) {
        String c = code.trim().toUpperCase();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", c)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", code));
        assertHodOwns(dept);                                // an HOD restores only their own department's courses
        jdbc.sql("SELECT catalogue.restore_course(:c)").param("c", c).query().singleRow();
        ensureCurrentOffering(c);                           // so it shows for registration without re-opening
        return Map.of("code", c, "state", "LIVE");
    }

    /** make one course Live: a BOARD/SENATE course becomes LIVE (an uploaded, approved course) */
    @PostMapping("/courses/{code}/live")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> makeLive(@PathVariable String code) {
        String c = code.trim().toUpperCase();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", c)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", code));
        assertHodOwns(dept);                                // an HOD acts only within their own department
        jdbc.sql("SELECT catalogue.make_course_live(:c)").param("c", c).query().singleRow();
        ensureCurrentOffering(c);                           // so it shows for registration without re-opening
        return Map.of("code", c, "state", "LIVE");
    }

    /** make every awaiting-approval course in a department Live in one action (optionally one level) */
    @PostMapping("/courses/live-all")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> makeDeptLive(@RequestParam String dept, @RequestParam(required = false) Integer level) {
        String d = scope.scopedDept(dept);                  // an HOD's bulk action stays within their department
        int n = jdbc.sql("""
                UPDATE catalogue.course SET state = 'LIVE'
                 WHERE dept_code = :d AND state IN ('BOARD', 'SENATE')
                   AND (:lvl::int IS NULL OR level = :lvl)
                """).param("d", d).param("lvl", level, java.sql.Types.INTEGER).update();
        // create offerings for the now-live courses so they appear in registration for the current session
        String session = jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1")
                .query(String.class).optional().orElse(null);
        int offered = 0;
        if (session != null && n > 0) {
            offered = jdbc.sql("""
                    INSERT INTO catalogue.offering (id, course_code, session, semester)
                    SELECT gen_random_uuid(), c.code, :ses, c.semester
                      FROM catalogue.course c
                     WHERE c.dept_code = :d AND c.state = 'LIVE'
                       AND (:lvl::int IS NULL OR c.level = :lvl)
                       AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
                       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                        WHERE o.course_code = c.code AND o.session = :ses AND o.semester = c.semester)
                    """).param("d", d).param("ses", session).param("lvl", level, java.sql.Types.INTEGER).update();
        }
        return Map.of("dept", d, "made_live", n, "offerings_created", offered);
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
