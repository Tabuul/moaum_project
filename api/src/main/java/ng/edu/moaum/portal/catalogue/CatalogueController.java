package ng.edu.moaum.portal.catalogue;

import java.util.List;
import java.util.Map;

import jakarta.validation.Valid;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
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
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** A department's course catalogue (V042). */
@RestController
@RequestMapping("/api/v1/catalogue")
class CatalogueController {

    private static final String OWNERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";
    /** a programme's structure is kept by the owners and, on the user's word (V460), the Director of ICT */
    private static final String STRUCTURE = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_ict')";
    private static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super','OFFICE_lecturer','OFFICE_exams','OFFICE_facultyexams','OFFICE_facultyofficer','OFFICE_records','OFFICE_dvc','OFFICE_vc','OFFICE_ict')";

    /** the Director of ICT alone creates, uploads, archives or removes faculties, departments, programmes and course structures */
    private static final String UPLOADERS = "hasAuthority('OFFICE_ict')";
    /** opening registration for a session is not a structure upload: the offices that could before still can */
    private static final String OPENERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_super','OFFICE_admin','OFFICE_hod','OFFICE_dean','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar')";

    private final JdbcClient jdbc;
    private final tools.jackson.databind.ObjectMapper json;
    private final ng.edu.moaum.portal.shared.OfficeScope scope;
    private final OfferAuthority authority;

    CatalogueController(JdbcClient jdbc, tools.jackson.databind.ObjectMapper json, ng.edu.moaum.portal.shared.OfficeScope scope, OfferAuthority authority) {
        this.jdbc = jdbc;
        this.json = json;
        this.scope = scope;
        this.authority = authority;
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

    /** V332: a course is created with the programmes that offer it — the owner's own bound at once, another department's proposed */
    public record FirstOffer(@NotBlank @Size(max = 12) String programme, @NotNull @Min(100) @Max(900) Integer level,
                             @Size(max = 12) String basis, @Size(max = 12) String track, @Size(max = 2000) String reason) {
    }

    public record NewCourse(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 120) String title,
                            @NotNull @Min(0) Integer units, @NotNull Integer semester, @NotNull Integer level,
                            @NotBlank @Size(max = 12) String dept, @Size(max = 20) String kind, @Valid List<FirstOffer> offers,
                            Boolean bothSemesters) {
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
        Map<String, Object> out = new java.util.LinkedHashMap<>(jdbc.sql("SELECT * FROM catalogue.import_courses(:p, :j::jsonb, :curr)")
                .param("p", body.programme()).param("j", json.writeValueAsString(body.rows()))
                .param("curr", body.curriculum() == null || body.curriculum().isBlank() ? null : body.curriculum().trim().toUpperCase(), java.sql.Types.VARCHAR)
                .query().singleRow());
        // V405/V406: a course uploaded while a semester's classes are already open gets its class now, by the upload's own act —
        // the codes as the pool holds them (an alias or another spelling resolves to the course), nothing by a trigger
        String[] codes = body.rows().stream().map(r -> r.get("code")).filter(c -> c != null && !String.valueOf(c).isBlank()).map(String::valueOf).distinct().toArray(String[]::new);
        int opened = codes.length == 0 ? 0 : jdbc.sql("""
                SELECT catalogue.open_classes_for_courses(ARRAY(SELECT DISTINCT catalogue.resolve_course_code(x) FROM unnest(:c::text[]) x
                                                                WHERE catalogue.resolve_course_code(x) IS NOT NULL))
                """).param("c", codes).query(Integer.class).single();
        out.put("classes_opened", opened);
        return out;
    }

    public record PlacementsIn(@jakarta.validation.constraints.NotNull @jakarta.validation.constraints.Size(max = 2000) List<Map<String, Object>> groups) {
    }

    /** V369: what loading these structures would do to the GST and EPS offices' courses, course by course — read, nothing written */
    @PostMapping("/import/placements")
    @PreAuthorize(UPLOADERS)
    @Transactional(readOnly = true)
    Object importPlacements(@Valid @RequestBody PlacementsIn body) {
        String out = jdbc.sql("SELECT catalogue.structure_placements(:g::jsonb)::text").param("g", json.writeValueAsString(body.groups())).query(String.class).single();
        return json.readValue(out, Object.class);
    }

    /** V460: what loading these structures would do to the units each programme takes an existing course at — the file's units
     *  go on the programme's binding where they differ from the course's, and the course's own units stay as they are for every
     *  other programme; listed course by course where the programme's units would change, read, nothing written */
    @PostMapping("/import/units")
    @PreAuthorize(UPLOADERS)
    @Transactional(readOnly = true)
    Map<String, Object> importUnits(@Valid @RequestBody PlacementsIn body) {
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH g AS (
                    SELECT upper(btrim(x->>'programme')) AS programme, r
                      FROM jsonb_array_elements(CAST(:g AS jsonb)) x, jsonb_array_elements(coalesce(x->'rows', '[]'::jsonb)) r),
                f AS (
                    SELECT DISTINCT ON (code, programme, level) *
                      FROM (SELECT g.programme,
                                   coalesce(catalogue.resolve_course_code(regexp_replace(upper(btrim(coalesce(g.r->>'code', g.r->>'courseCode', g.r->>'course_code', ''))), '[[:space:]]+', ' ', 'g')),
                                            regexp_replace(upper(btrim(coalesce(g.r->>'code', g.r->>'courseCode', g.r->>'course_code', ''))), '[[:space:]]+', ' ', 'g')) AS code,
                                   least(nullif(regexp_replace(coalesce(g.r->>'units', ''), '[^0-9]', '', 'g'), '')::int, 12) AS file_units,
                                   nullif(regexp_replace(coalesce(g.r->>'level', ''), '[^0-9]', '', 'g'), '')::int AS level
                              FROM g) z
                     WHERE file_units > 0 AND level IS NOT NULL)
                SELECT f.code, c.title, f.programme, f.level, f.file_units AS "fileUnits", c.units AS "courseUnits",
                       catalogue.units_for(f.code, f.programme, f.level) AS "nowUnits", d.name AS department,
                       CASE WHEN f.file_units <> c.units THEN 'PROGRAMME_OWN' ELSE 'BACK_TO_COURSE' END AS change
                  FROM f
                  JOIN catalogue.course c ON c.code = f.code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE f.file_units IS DISTINCT FROM catalogue.units_for(f.code, f.programme, f.level)
                 ORDER BY f.programme, f.level, f.code
                """).param("g", json.writeValueAsString(body.groups())).query().listOfRows();
        long own = rows.stream().filter(r -> "PROGRAMME_OWN".equals(r.get("change"))).count();
        return Map.of("rows", rows, "counts", Map.of("programmeOwn", own, "backToCourse", rows.size() - own));
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
                SELECT c.id, c.code, c.title, c.units, c.semester, c.both_semesters, c.level, c.kind, c.state, c.ended_on, c.curriculum, c.ca_max,
                       (SELECT count(*) FROM catalogue.offer_proposal pr WHERE pr.course_code = c.code AND pr.state = 'PENDING') AS pending,
                       (SELECT CASE WHEN p.id IS NULL THEN NULL ELSE p.surname || ', ' || p.given_names END
                          FROM catalogue.offering o LEFT JOIN iam.person p ON p.id = o.lecturer_id
                         WHERE o.course_code = c.code AND o.session = (SELECT name FROM cur) AND o.stream = 'REGULAR'
                         ORDER BY o.semester LIMIT 1) AS lecturer,
                       EXISTS (SELECT 1 FROM catalogue.offering o2 WHERE o2.course_code = c.code AND o2.session = (SELECT name FROM cur) AND o2.stream = 'REGULAR') AS offered,
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
                SELECT co.level, c.semester, c.both_semesters, c.code, c.title, coalesce(co.units, c.units) AS units, co.units AS own_units, c.units AS course_units,
                       c.kind, c.state, c.dept_code, d.name AS dept_name, co.basis, co.track, c.ca_max
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
        List<Map<String, Object>> tracks = jdbc.sql("SELECT code, label AS name FROM policy.curriculum_track ORDER BY ord, code").query().listOfRows();   // V332: the track carries a label, not a name
        return Map.of("programme", programme, "rows", rows, "limits", limits, "tracks", tracks);
    }

    /** units (V460): the units this programme takes the course at; the course's own number takes the course's units, and none
     *  given keeps what the binding has — so a change of basis or track never drops a programme's own units */
    public record BindIn(@NotBlank @Size(max = 12) String programme, @NotBlank @Size(max = 24) String course,
                         @NotNull @Min(100) @Max(600) Integer level, @Size(max = 12) String basis, @Size(max = 12) String track,
                         @Min(0) @Max(12) Integer units) {
    }

    /** bind a course into a programme's structure at a level, on a basis, for a track (or every track), at the programme's units */
    @PostMapping("/structure/bind")
    @PreAuthorize(STRUCTURE)
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
                INSERT INTO catalogue.course_offer (course_code, programme_code, level, basis, track, units)
                VALUES (:c, :p, :l, :b, :t, CASE WHEN CAST(:u AS int) IS DISTINCT FROM (SELECT x.units FROM catalogue.course x WHERE x.code = :c) THEN CAST(:u AS int) END)
                ON CONFLICT (course_code, programme_code, level) DO UPDATE SET basis = EXCLUDED.basis, track = EXCLUDED.track,
                       units = CASE WHEN :given THEN EXCLUDED.units ELSE catalogue.course_offer.units END
                """).param("c", c).param("p", p).param("l", body.level()).param("b", basis).param("t", track, java.sql.Types.VARCHAR)
                .param("u", body.units(), java.sql.Types.INTEGER).param("given", body.units() != null).update();
        int units = jdbc.sql("SELECT catalogue.units_for(:c, :p, :l)").param("c", c).param("p", p).param("l", body.level()).query(Integer.class).single();
        return Map.of("programme", p, "course", c, "level", body.level(), "basis", basis, "track", track == null ? "" : track, "units", units);
    }

    /** unbind a course from a programme at a level — refused while a student of that programme and level is registered on it this session */
    @DeleteMapping("/structure/bind")
    @PreAuthorize(STRUCTURE)
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

    /** V464: what setting a programme's units for a course at a level would reach — the units now and after, how many
     *  registrations follow, and how many keep theirs (a closed session, or a class whose results are worked on) */
    private Map<String, Object> impactOf(String c, String p, int level, int units) {
        boolean bound = jdbc.sql("SELECT EXISTS (SELECT 1 FROM catalogue.course_offer WHERE course_code = :c AND programme_code = :p AND level = :l)")
                .param("c", c).param("p", p).param("l", level).query(Boolean.class).single();
        if (!bound) throw new ng.edu.moaum.portal.shared.NotFound("binding", c + " → " + p + " at " + level);
        return jdbc.sql("""
                SELECT now_units AS "nowUnits", new_units AS "newUnits", follow, kept FROM catalogue.units_change_impact(:c, :p, :l, :u)
                """).param("c", c).param("p", p).param("l", level).param("u", units).query().singleRow();
    }

    @GetMapping("/structure/units-impact")
    @PreAuthorize(STRUCTURE)
    @Transactional(readOnly = true)
    Map<String, Object> unitsImpact(@RequestParam String programme, @RequestParam String course, @RequestParam int level, @RequestParam int units) {
        String p = programme.trim().toUpperCase();
        String c = course.trim().toUpperCase();
        assertHodOwns(programmeDept(p));
        if (units < 0 || units > 12) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_UNITS", "A programme takes a course at 0 to 12 units.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Give a number from 0 to 12.", "Head of Department"));
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>(impactOf(c, p, level, units));
        out.put("held", heldClasses("SELECT * FROM catalogue.units_change_rows(:c, :p, :l, :u)", Map.of("c", c, "p", p, "l", level, "u", units)));
        return out;
    }

    /** V465: the classes a change leaves as they are — a closed session, or results worked on — each with the sheet its units
     *  correction is raised on (none for a closed session's class without one), the latest first */
    private List<Map<String, Object>> heldClasses(String rows, Map<String, Object> params) {
        return jdbc.sql("""
                SELECT o.session, o.semester, o.course_code AS course, count(*) AS registrations,
                       (SELECT sh.id FROM assessment.score_sheet sh WHERE sh.offering_id = x.offering_id
                         ORDER BY sh.exam_session_id IS NOT NULL, sh.id LIMIT 1) AS "sheetId",
                       coalesce((SELECT a.state = 'CLOSED' FROM policy.academic_session a WHERE a.name = o.session), false) AS closed
                  FROM (%s) x JOIN catalogue.offering o ON o.id = x.offering_id
                 WHERE x.held AND x.old_units IS DISTINCT FROM x.to_units
                 GROUP BY o.session, o.semester, o.course_code, x.offering_id
                 ORDER BY o.session DESC, o.semester DESC LIMIT 50
                """.formatted(rows)).params(params).query().listOfRows();
    }

    /** V465: what a change of the course's own units would reach, before it is made — the registrations that follow, those that
     *  keep theirs, the other departments' programmes left at the old number, and the classes that keep their units */
    @GetMapping("/courses/{code}/units-impact")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> courseUnitsImpact(@PathVariable String code, @RequestParam int units) {
        String c = code.trim().toUpperCase();
        if (units < 0 || units > 12) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_UNITS", "A course carries 0 to 12 units.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Give a number from 0 to 12.", "Head of Department"));
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>(jdbc.sql("""
                SELECT now_units AS "nowUnits", new_units AS "newUnits", follow, kept, pinned FROM catalogue.course_units_change_impact(:c, :u)
                """).param("c", c).param("u", units).query().listOfRows().stream().findFirst()
                .filter(r -> r.get("nowUnits") != null).orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", c)));
        out.put("pinnedProgrammes", ((Number) out.get("pinned")).intValue() == 0 ? List.of() : jdbc.sql("""
                SELECT x.programme_code AS programme, p.name, x.level, d.name AS department
                  FROM catalogue.units_pinned_by_course(:c) x JOIN ref.programme p ON p.code = x.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 ORDER BY d.name, p.name, x.level
                """).param("c", c).query().listOfRows());
        out.put("held", heldClasses("SELECT * FROM catalogue.course_units_change_rows(:c, :u)", Map.of("c", c, "u", units)));
        return out;
    }

    public record UnitsIn(@NotBlank @Size(max = 12) String programme, @NotBlank @Size(max = 24) String course,
                          @NotNull @Min(100) @Max(900) Integer level, @NotNull @Min(0) @Max(12) Integer units) {
    }

    /** V464: set the units a programme takes a course at, at a level — the binding's basis and track untouched, the course's own
     *  number taking the course's units again; the registrations not yet examined follow, and the answer says how many */
    @PostMapping("/structure/units")
    @PreAuthorize(STRUCTURE)
    @Transactional
    Map<String, Object> setUnits(@Valid @RequestBody UnitsIn body) {
        String p = body.programme().trim().toUpperCase();
        String c = body.course().trim().toUpperCase();
        assertHodOwns(programmeDept(p));
        Map<String, Object> impact = impactOf(c, p, body.level(), body.units());
        jdbc.sql("""
                UPDATE catalogue.course_offer co SET units = nullif(:u, (SELECT x.units FROM catalogue.course x WHERE x.code = co.course_code))
                 WHERE co.course_code = :c AND co.programme_code = :p AND co.level = :l
                """).param("u", body.units()).param("c", c).param("p", p).param("l", body.level()).update();
        int units = jdbc.sql("SELECT catalogue.units_for(:c, :p, :l)").param("c", c).param("p", p).param("l", body.level()).query(Integer.class).single();
        return Map.of("programme", p, "course", c, "level", body.level(), "units", units, "followed", impact.get("follow"), "kept", impact.get("kept"));
    }

    /** a course anywhere in the University, by code or title, for the structure's picker */
    @GetMapping("/courses/search")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> searchCourses(@RequestParam String q) {
        String needle = "%" + q.trim().toLowerCase() + "%";
        if (q.trim().length() < 2) return List.of();
        return jdbc.sql("""
                SELECT c.code, c.title, c.units, c.semester, c.both_semesters, c.level, c.kind, c.state, c.dept_code, d.name AS dept_name
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
    Map<String, Object> setCurriculum(@PathVariable String code, @Valid @RequestBody CurriculumIn body) {
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
       level, semester and title; the cleanest code is the keeper, the rest are duplicates.
       A BSU- code and a MOAU- code of the same course are NOT duplicates: the University keeps both —
       students in 300 level and above carry the BSU- code, those in 100 and 200 level the MOAU- code, the
       same course taught by the same lecturer. In a group that holds either, each of the
       two families keeps its cleanest code; anything else in the group (an unprefixed or combined code, a
       second code of the same family) is the duplicate. */
    private static final String DUPLICATES_CTE = """
            WITH offered AS (
                SELECT c.code, c.title, c.level, c.semester, coalesce(c.curriculum, '') AS curr,
                       lower(regexp_replace(btrim(c.title), '\\s+', ' ', 'g')) AS norm_title,
                       (c.code LIKE '%/%' OR c.code LIKE '%-%')::int AS messy,
                       (c.code ~ '^[A-Z]{2,4} [0-9]{3}$')::int AS clean,
                       CASE WHEN c.code ~ '^BSU-' THEN 'BSU' WHEN c.code ~ '^MOAU-' THEN 'MOAU' END AS family
                  FROM catalogue.course c
                 WHERE c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %' AND c.dept_code = :dept),
            ranked AS (
                -- partition by curriculum too: a BMAS course and its CCMAS counterpart are two
                -- curricula, not a duplicate to end (V116/V160), so they never group together
                SELECT o.*,
                       count(*) OVER g AS n,
                       count(o.family) OVER g AS in_family,
                       row_number() OVER (PARTITION BY level, semester, norm_title, curr ORDER BY messy ASC, clean DESC, length(code) ASC, code ASC) AS rnk,
                       row_number() OVER (PARTITION BY level, semester, norm_title, curr, family ORDER BY messy ASC, clean DESC, length(code) ASC, code ASC) AS family_rnk
                  FROM offered o
                WINDOW g AS (PARTITION BY level, semester, norm_title, curr)),
            kept AS (
                SELECT r.*, CASE WHEN r.in_family > 0 THEN r.family IS NOT NULL AND r.family_rnk = 1 ELSE r.rnk = 1 END AS keeper
                  FROM ranked r),
            grp AS (
                SELECT k.*, count(*) FILTER (WHERE NOT k.keeper) OVER (PARTITION BY level, semester, norm_title, curr) AS extra
                  FROM kept k)
            """;

    /** the duplicate courses in a department: each group's keeper and the codes that would be ended */
    @GetMapping("/duplicates")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> duplicates(@RequestParam String dept) {
        return jdbc.sql(DUPLICATES_CTE + """
                SELECT level, semester, title, code, keeper
                  FROM grp WHERE n > 1 AND extra > 0
                 ORDER BY level, semester, norm_title, NOT keeper, rnk
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
                 WHERE c.code = grp.code AND grp.n > 1 AND NOT grp.keeper AND c.state <> 'ENDED'
                """).param("dept", scope.scopedDept(dept)).update();
        return Map.of("ended", ended, "dept", scope.scopedDept(dept));
    }

    /** V329: the duplicate codes removed outright where nothing carries them, and ended where a record does;
     *  the keeper of each group is untouched; what happened to each code is returned */
    @PostMapping("/duplicates/remove")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> removeDuplicates(@RequestParam String dept) {
        String d = scope.scopedDept(dept);
        List<String> codes = jdbc.sql(DUPLICATES_CTE + "SELECT code FROM grp WHERE n > 1 AND NOT keeper ORDER BY level, semester, norm_title, rnk")
                .param("dept", d).query(String.class).list();
        List<Map<String, Object>> outcomes = codes.isEmpty() ? List.of()
                : jdbc.sql("SELECT * FROM catalogue.remove_or_end(string_to_array(:codes, E'\\n'))").param("codes", String.join("\n", codes)).query().listOfRows();
        long removed = outcomes.stream().filter(o -> "REMOVED".equals(o.get("outcome"))).count();
        long ended = outcomes.stream().filter(o -> "ENDED".equals(o.get("outcome"))).count();
        return Map.of("dept", d, "removed", removed, "ended", ended, "outcomes", outcomes);
    }

    /* ── V396: a BSU- course and its MOAU- twin, taught as one ── */

    public record TwinIn(@NotBlank @Size(max = 20) String bsuCode, @NotBlank @Size(max = 20) String moauCode) {
    }

    public record UnlinkIn(@NotBlank @Size(max = 300) String reason) {
    }

    /** the department's linked pairs — with how each pair's classes stand in the University's current session — and the pairs
     *  the duplicates rule suggests linking */
    @GetMapping("/twins")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> twins(@RequestParam String dept) {
        String d = scope.scopedDept(dept);
        String session = jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
        List<Map<String, Object>> linked = jdbc.sql("""
                SELECT t.id, t.bsu_code, b.title AS bsu_title, t.moau_code, m.title AS moau_title, b.level, b.semester, t.linked_at,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS linked_by,
                       ob.id AS bsu_offering, om.id AS moau_offering,
                       CASE WHEN ob.id IS NULL OR om.id IS NULL THEN 'NO_CLASSES'
                            WHEN ob.lecturer_id IS NULL AND om.lecturer_id IS NULL THEN 'UNALLOCATED'
                            WHEN ob.lecturer_id IS NOT DISTINCT FROM om.lecturer_id THEN 'TOGETHER'
                            ELSE 'DIFFERENT' END AS allocation,
                       nullif(btrim(coalesce(lb.surname, '') || ', ' || coalesce(lb.given_names, '')), ',') AS lecturer
                  FROM catalogue.course_twin t
                  JOIN catalogue.course b ON b.code = t.bsu_code
                  JOIN catalogue.course m ON m.code = t.moau_code
                  LEFT JOIN iam.person p ON p.id = t.linked_by
                  LEFT JOIN catalogue.offering ob ON ob.course_code = t.bsu_code AND ob.session = :s AND ob.semester = b.semester AND ob.stream = 'REGULAR'
                  LEFT JOIN catalogue.offering om ON om.course_code = t.moau_code AND om.session = :s AND om.semester = m.semester AND om.stream = 'REGULAR'
                  LEFT JOIN iam.person lb ON lb.id = coalesce(ob.lecturer_id, om.lecturer_id)
                 WHERE t.unlinked_at IS NULL AND b.dept_code = :d
                 ORDER BY b.level, b.semester, t.bsu_code
                """).param("s", session, java.sql.Types.VARCHAR).param("d", d).query().listOfRows();
        List<Map<String, Object>> suggested = jdbc.sql("SELECT * FROM catalogue.twin_suggestions(:d)").param("d", d).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("dept", d);
        out.put("session", session);
        out.put("linked", linked);
        out.put("suggested", suggested);
        return out;
    }

    /** a pair linked by the department or a central office: the classes of sessions still running are aligned at once */
    @PostMapping("/twins")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> linkTwin(@Valid @RequestBody TwinIn body) {
        scope.assertCourseInScope(body.bsuCode());
        scope.assertCourseInScope(body.moauCode());
        java.util.UUID id = jdbc.sql("SELECT catalogue.link_twin(:b, :m)").param("b", body.bsuCode()).param("m", body.moauCode()).query(java.util.UUID.class).single();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = upper(btrim(:b))").param("b", body.bsuCode()).query(String.class).single();
        Map<String, Object> out = new java.util.LinkedHashMap<>(twins(dept));
        out.put("linkedId", id);
        return out;
    }

    /** undone with a reason; each code keeps what it has and is its own class from then */
    @PostMapping("/twins/{id}/unlink")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> unlinkTwin(@PathVariable java.util.UUID id, @Valid @RequestBody UnlinkIn body) {
        String bsu = jdbc.sql("SELECT bsu_code FROM catalogue.course_twin WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("linked pair", id));
        scope.assertCourseInScope(bsu);
        jdbc.sql("SELECT catalogue.unlink_twin(:id, :r)").param("id", id).param("r", body.reason()).query().listOfRows();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :b").param("b", bsu).query(String.class).single();
        return twins(dept);
    }

    private static final String CENTRAL = "hasAnyAuthority('OFFICE_academic','OFFICE_dregistrar','OFFICE_registrar','OFFICE_admin','OFFICE_super')";

    public record TwinsIn(@NotNull @Size(max = 500) List<@Valid TwinIn> pairs) {
    }

    /** every department's pairs at once, for the central offices before a session: the pairs the duplicates rule suggests, by
     *  department, and the linked pairs with how each stands in the University's current session */
    @GetMapping("/twins/all")
    @PreAuthorize(CENTRAL)
    @Transactional(readOnly = true)
    /** @param session the session whose classes say whether a linked pair is allocated together; the University's current one when not named */
    Map<String, Object> twinsAll(@RequestParam(required = false) String session) {
        String s = session == null || session.isBlank() ? jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null) : session.trim();
        List<Map<String, Object>> suggested = jdbc.sql("""
                SELECT d.code AS dept, d.name AS dept_name, s.bsu_code, s.bsu_title, s.moau_code, s.moau_title, s.level, s.semester
                  FROM ref.department d CROSS JOIN LATERAL catalogue.twin_suggestions(d.code) s
                 ORDER BY d.name, s.level, s.semester, s.bsu_code
                """).query().listOfRows();
        List<Map<String, Object>> linked = jdbc.sql("""
                SELECT t.id, b.dept_code AS dept, d.name AS dept_name, t.bsu_code, b.title AS bsu_title, t.moau_code, b.level, b.semester, t.linked_at,
                       CASE WHEN ob.id IS NULL OR om.id IS NULL THEN 'NO_CLASSES'
                            WHEN ob.lecturer_id IS NULL AND om.lecturer_id IS NULL THEN 'UNALLOCATED'
                            WHEN ob.lecturer_id IS NOT DISTINCT FROM om.lecturer_id THEN 'TOGETHER'
                            ELSE 'DIFFERENT' END AS allocation,
                       nullif(btrim(coalesce(lb.surname, '') || ', ' || coalesce(lb.given_names, '')), ',') AS lecturer
                  FROM catalogue.course_twin t
                  JOIN catalogue.course b ON b.code = t.bsu_code
                  JOIN ref.department d ON d.code = b.dept_code
                  LEFT JOIN catalogue.offering ob ON ob.course_code = t.bsu_code AND ob.session = :s AND ob.semester = b.semester AND ob.stream = 'REGULAR'
                  LEFT JOIN catalogue.offering om ON om.course_code = t.moau_code AND om.session = :s AND om.semester = b.semester AND om.stream = 'REGULAR'
                  LEFT JOIN iam.person lb ON lb.id = coalesce(ob.lecturer_id, om.lecturer_id)
                 WHERE t.unlinked_at IS NULL
                 ORDER BY d.name, b.level, b.semester, t.bsu_code
                """).param("s", s, java.sql.Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("session", s);
        out.put("suggested", suggested);
        out.put("linked", linked);
        return out;
    }

    /** many pairs linked in one act by a central office; a pair the rule refuses (not one course, already linked) is reported
     *  by its code and the rest are linked all the same */
    @PostMapping("/twins/link-all")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> linkAll(@Valid @RequestBody TwinsIn body) {
        int linked = 0;
        List<Map<String, Object>> refused = new java.util.ArrayList<>();
        int i = 0;
        for (TwinIn p : body.pairs()) {
            String sp = "twin_" + (i++);
            jdbc.sql("SAVEPOINT " + sp).update();
            try {
                jdbc.sql("SELECT catalogue.link_twin(:b, :m)").param("b", p.bsuCode()).param("m", p.moauCode()).query().listOfRows();
                jdbc.sql("RELEASE SAVEPOINT " + sp).update();
                linked++;
            } catch (org.springframework.dao.DataAccessException e) {
                jdbc.sql("ROLLBACK TO SAVEPOINT " + sp).update();
                Throwable root = e.getMostSpecificCause();
                // the server's own message ("COURSE_TWIN_TAKEN: ..."), not the driver's, which prefixes "ERROR: " and appends where it arose
                String message = root instanceof org.postgresql.util.PSQLException pg && pg.getServerErrorMessage() != null && pg.getServerErrorMessage().getMessage() != null
                        ? pg.getServerErrorMessage().getMessage() : root == null || root.getMessage() == null ? "refused" : root.getMessage();
                java.util.regex.Matcher m = java.util.regex.Pattern.compile("^([A-Z][A-Z0-9_]{3,60}): (.+)$", java.util.regex.Pattern.DOTALL).matcher(message.trim());
                refused.add(Map.of("bsuCode", p.bsuCode(), "moauCode", p.moauCode(),
                        "code", m.matches() ? m.group(1) : "REFUSED", "detail", m.matches() ? m.group(2).trim() : message.trim()));
            }
        }
        Map<String, Object> out = new java.util.LinkedHashMap<>(twinsAll(null));
        out.put("linkedNow", linked);
        out.put("refused", refused);
        return out;
    }

    /* ── V443: the code names the owner ── */

    public record CodeOwnerIn(@jakarta.validation.constraints.NotBlank @jakarta.validation.constraints.Size(max = 120) String department,
                              @jakarta.validation.constraints.Size(max = 400) String note, Boolean apply, @jakarta.validation.constraints.Size(max = 400) String reason) { }

    /** every course-code prefix of the pool: whether it is a department's own code (its courses are that department's by rule), which
     *  department the Academic Office named for it otherwise, who holds its courses now, and how many live courses sit astray */
    @GetMapping("/code-owners")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> codeOwners() {
        return Map.of("rows", jdbc.sql("SELECT * FROM catalogue.code_owners()").query().listOfRows(),
                "departments", jdbc.sql("SELECT code, name FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
    }

    /** a prefix that is no department's own code, named to its department — and, when asked, its courses moved there on the owner trail */
    @PutMapping("/code-owners/{prefix}")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> setCodeOwner(@PathVariable String prefix, @Valid @RequestBody CodeOwnerIn body) {
        ng.edu.moaum.portal.shared.AuditContext ctx = ng.edu.moaum.portal.shared.AuditContextHolder.required();
        int moved = jdbc.sql("SELECT catalogue.set_code_prefix(:p, :d, :n, :a, :r, :actor, :office)")
                .param("p", prefix.trim().toUpperCase()).param("d", body.department().trim()).param("n", body.note(), java.sql.Types.VARCHAR)
                .param("a", Boolean.TRUE.equals(body.apply())).param("r", body.reason(), java.sql.Types.VARCHAR)
                .param("actor", ctx.actorId()).param("office", ctx.actorOffice()).query(Integer.class).single();
        return Map.of("prefix", prefix.trim().toUpperCase(), "moved", moved);
    }

    /** the courses of a prefix moved to the department the code names — a department's own code, or one named here */
    @PostMapping("/code-owners/{prefix}/apply")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> applyCodeOwner(@PathVariable String prefix, @RequestBody(required = false) Map<String, String> body) {
        ng.edu.moaum.portal.shared.AuditContextHolder.required();
        int moved = jdbc.sql("SELECT catalogue.apply_code_owners(:p, :r)").param("p", prefix.trim().toUpperCase())
                .param("r", body == null ? null : body.get("reason"), java.sql.Types.VARCHAR).query(Integer.class).single();
        return Map.of("prefix", prefix.trim().toUpperCase(), "moved", moved);
    }

    @DeleteMapping("/code-owners/{prefix}")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> unsetCodeOwner(@PathVariable String prefix) {
        ng.edu.moaum.portal.shared.AuditContext ctx = ng.edu.moaum.portal.shared.AuditContextHolder.required();
        boolean removed = jdbc.sql("SELECT catalogue.unset_code_prefix(:p, :o)").param("p", prefix.trim().toUpperCase()).param("o", ctx.actorOffice()).query(Boolean.class).single();
        return Map.of("prefix", prefix.trim().toUpperCase(), "removed", removed);
    }

    /** V402: a BSU- code and its MOAU- twin are both offered, and a student is shown their cohort's — MOAU- for the cohorts
     *  admitted from the entry session stated here, BSU- for the cohorts before it (their carry-overs come by code). Unstated,
     *  both reach everyone. The pairs are not linked: V396's link stays available but is no longer suggested. */
    @GetMapping("/code-families")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> codeFamilies() {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT f.moau_from_entry_session, f.stated_at,
                       nullif(btrim(coalesce(p.surname, '') || ', ' || coalesce(p.given_names, '')), ',') AS stated_by
                  FROM catalogue.code_family_setting f
                  LEFT JOIN iam.person p ON p.id = f.stated_by
                 WHERE f.id = 1
                """).query().listOfRows();
        Map<String, Object> out = new java.util.LinkedHashMap<>(rows.isEmpty() ? Map.of() : rows.get(0));
        out.put("pairs", jdbc.sql("SELECT count(*) FROM catalogue.course b WHERE b.code ~ '^BSU-' AND b.state <> 'ENDED' AND catalogue.twin_by_code(b.code) IS NOT NULL").query(Long.class).single());
        out.put("linked_pairs", jdbc.sql("SELECT count(*) FROM catalogue.course_twin WHERE unlinked_at IS NULL").query(Long.class).single());
        out.put("current_session", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        return out;
    }

    public record CodeFamilyIn(@Pattern(regexp = "\\d{4}/\\d{4}") String moauFromEntrySession) {
    }

    /** the rule stated (or unstated, with null) by a central office; the person is on the audit row and kept here for the page */
    @PutMapping("/code-families")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> setCodeFamilies(@Valid @RequestBody CodeFamilyIn body) {
        jdbc.sql("""
                UPDATE catalogue.code_family_setting
                   SET moau_from_entry_session = :s, stated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid, stated_at = now()
                 WHERE id = 1
                """).param("s", body.moauFromEntrySession(), java.sql.Types.VARCHAR).update();
        return codeFamilies();
    }

    /** V413: the registration lines of a session holding the other family's code of a course — students registered before V402's rule */
    @GetMapping("/code-families/mismatches")
    @PreAuthorize(CENTRAL)
    @Transactional(readOnly = true)
    List<Map<String, Object>> codeFamilyMismatches(@RequestParam(required = false) String session) {
        String s = session == null || session.isBlank() ? jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null) : session.trim();
        return jdbc.sql("SELECT * FROM catalogue.other_family_registrations(:s)").param("s", s, java.sql.Types.VARCHAR).query().listOfRows();
    }

    public record MoveIn(@NotNull java.util.UUID registrationId, @NotNull java.util.UUID offeringId, @NotBlank @Size(max = 300) String reason) {
    }

    /** one line moved to the cohort's class of the same session, semester and stream (opened if owed); refused where a score is on it */
    @PostMapping("/code-families/mismatches/move")
    @PreAuthorize(CENTRAL)
    @Transactional
    Map<String, Object> moveToOwnCode(@Valid @RequestBody MoveIn body) {
        java.util.UUID to = jdbc.sql("SELECT catalogue.move_entry_to_own_code(:r, :o, :why)")
                .param("r", body.registrationId()).param("o", body.offeringId()).param("why", body.reason()).query(java.util.UUID.class).single();
        return Map.of("registrationId", body.registrationId(), "movedTo", to);
    }

    /** every course offered to a programme, level by level — the view for the course-upload desk */
    @GetMapping("/offered")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> offered(@RequestParam String programme) {
        return jdbc.sql("""
                SELECT c.code, c.title, c.units, co.level, c.semester, c.both_semesters, c.kind, co.basis,
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
                       d.name AS department, co.level, c.semester, c.both_semesters, c.code, c.title, c.units,
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
                SELECT c.code, c.title, c.dept_code, d.name AS dept_name, c.units, c.level, c.semester, c.both_semesters
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
        if (Boolean.TRUE.equals(body.bothSemesters()) && body.semester() != null && body.semester() == 3) {
            throw new ng.edu.moaum.portal.shared.DomainRuleViolation("CAT_SEMESTER_BOTH", "A course taught in both semesters is taught in the first and the second.",
                    new ng.edu.moaum.portal.shared.DomainRuleViolation.Remedy("Choose the first semester with both, or the third semester alone.", "Head of Department"));
        }
        String code = jdbc.sql("SELECT catalogue.create_course(:c, :t, :u, :s, :l, :d, :k)")
                .param("c", body.code()).param("t", body.title()).param("u", body.units()).param("s", body.semester())
                .param("l", body.level()).param("d", body.dept()).param("k", body.kind())
                .query(String.class).single();
        if (Boolean.TRUE.equals(body.bothSemesters())) {   // V386: taught in the first and the second semester alike
            jdbc.sql("UPDATE catalogue.course SET semester = 1, both_semesters = true WHERE code = :c").param("c", code).update();
        }
        // V332: the one course, offered to its first programmes — the owner's bound now, another department's proposed to it
        List<Map<String, Object>> outcomes = new java.util.ArrayList<>();
        for (FirstOffer o : body.offers() == null ? List.<FirstOffer>of() : body.offers()) {
            outcomes.add(authority.offer(code, body.dept().trim().toUpperCase(), o.programme(), o.level(), o.basis(), o.track(), o.reason()));
        }
        // a course the department adds is live at once, on its course list and in the current session's registration,
        // as an uploaded course is (V172) and a GST course is: it no longer waits on the Faculty Board and Senate
        jdbc.sql("SELECT catalogue.make_course_live(:c)").param("c", code).query().listOfRows();
        ensureCurrentOffering(code);
        Map<String, Object> out = new java.util.LinkedHashMap<>();
        out.put("code", code);
        out.put("id", jdbc.sql("SELECT id FROM catalogue.course WHERE code = :c").param("c", code).query(java.util.UUID.class).single());
        out.put("state", "LIVE");
        out.put("bound", outcomes.stream().filter(x -> "BOUND".equals(x.get("outcome"))).count());
        out.put("proposed", outcomes.stream().filter(x -> "PROPOSED".equals(x.get("outcome"))).count());
        out.put("offers", outcomes);
        return out;
    }

    @PostMapping("/courses/{code}/end")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> end(@PathVariable String code) {
        jdbc.sql("SELECT catalogue.end_course(:c)").param("c", code).query().singleRow();
        return Map.of("code", code, "state", "ENDED");
    }

    /** V329: a course removed outright — only when nothing carries it (no registration, result, score sheet, timetable,
     *  question bank, deferment or old-portal result); otherwise the database refuses with COURSE_CARRIED and the course
     *  is ended instead. For a code that never existed: a second upload of the same course, a mistyped code. */
    @DeleteMapping("/courses/{code}")
    @PreAuthorize(OWNERS)
    @Transactional
    Map<String, Object> remove(@PathVariable String code) {
        String c = code.trim().toUpperCase();
        String dept = jdbc.sql("SELECT dept_code FROM catalogue.course WHERE code = :c").param("c", c)
                .query(String.class).optional().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", code));
        assertHodOwns(dept);                                // an HOD removes only their own department's courses
        jdbc.sql("SELECT catalogue.remove_course(:c)").param("c", c).query().singleRow();
        return Map.of("code", c, "removed", true);
    }

    /** create the current-session offering for a live course, so it appears in registration at once.
     *  student_menu lists a course only when a catalogue.offering exists for the session and the
     *  course's semester; a course made live (or restored) after registration was opened has none. */
    private void ensureCurrentOffering(String code) {
        jdbc.sql("""
                INSERT INTO catalogue.offering (id, course_code, session, semester)
                SELECT gen_random_uuid(), c.code, cur.name, s.sem
                  FROM catalogue.course c
                  CROSS JOIN LATERAL unnest(catalogue.course_semesters(c.semester, c.both_semesters)) s(sem)   -- V386: each semester it is taught in
                  CROSS JOIN (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1) cur
                 WHERE c.code = :c AND c.state <> 'ENDED'
                   AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
                   AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                    WHERE o.course_code = c.code AND o.session = cur.name AND o.semester = s.sem AND o.stream = 'REGULAR')
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
                    SELECT gen_random_uuid(), c.code, :ses, s.sem
                      FROM catalogue.course c
                      CROSS JOIN LATERAL unnest(catalogue.course_semesters(c.semester, c.both_semesters)) s(sem)   -- V386: each semester it is taught in
                     WHERE c.dept_code = :d AND c.state = 'LIVE'
                       AND (:lvl::int IS NULL OR c.level = :lvl)
                       AND EXISTS (SELECT 1 FROM catalogue.course_offer co WHERE co.course_code = c.code)
                       AND NOT EXISTS (SELECT 1 FROM catalogue.offering o
                                        WHERE o.course_code = c.code AND o.session = :ses AND o.semester = s.sem AND o.stream = 'REGULAR')
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
