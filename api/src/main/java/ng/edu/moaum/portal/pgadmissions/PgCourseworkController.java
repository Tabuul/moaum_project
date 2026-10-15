package ng.edu.moaum.portal.pgadmissions;

import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Postgraduate coursework (V211): the course catalogue per programme, a student's registration for a
 * session/semester, and the scores that the department records (CA + examination → total → the
 * postgraduate grade A/B/C/F). Self-contained, with its own grade function, so the undergraduate
 * assessment engine is untouched. The student registers and sees their results; the department and
 * School define courses, endorse registrations and enter scores.
 */
@RestController
@RequestMapping("/api/v1/pg/coursework")
class PgCourseworkController {

    private static final String STUDENT = "hasAuthority('OFFICE_student')";
    private static final String DESK = "hasAnyAuthority('OFFICE_hod','OFFICE_academic','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";
    /** V389: the offices that open the School's classes in its session */
    private static final String SCHOOL = "hasAnyAuthority('OFFICE_academic','OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_super')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    PgCourseworkController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /* ── the Head of Department's bound (V337): a Head of Department reads, endorses and scores their own department's
          postgraduate coursework only; the School and the Academic Office read it all. The check is on the record, so an
          id typed into the address bar is refused the same way. ── */

    /** the department the acting Head of Department is held to, a sentinel that matches nothing when none resolves, or null */
    private String hodDept() {
        if (!scope.actingHod()) {
            return null;
        }
        String d = scope.actingDept();
        return d == null ? "__none__" : d;
    }

    private void programmeInBound(String programme) {
        String dept = hodDept();
        if (dept == null) {
            return;
        }
        String of = jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", programme == null ? "" : programme.trim())
                .query(String.class).optional().orElse(null);
        if (of != null && !dept.equalsIgnoreCase(of)) {
            throw new AccessDeniedException("This programme belongs to another department; the Head of Department manages their own department's postgraduate coursework only.");
        }
    }

    private void registrationInBound(UUID registration) {
        String dept = hodDept();
        if (dept == null) {
            return;
        }
        String of = jdbc.sql("""
                SELECT g.dept_code FROM admissions.pg_registration r JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme g ON g.code = s.programme_code WHERE r.id = :id
                """).param("id", registration).query(String.class).optional().orElse(null);
        if (of != null && !dept.equalsIgnoreCase(of)) {
            throw new AccessDeniedException("This registration is another department's; the Head of Department reads and endorses their own department's only.");
        }
    }

    private void entryInBound(UUID entry) {
        UUID registration = jdbc.sql("SELECT registration_id FROM admissions.pg_registration_entry WHERE id = :e")
                .param("e", entry).query(UUID.class).optional().orElse(null);
        if (registration != null) {
            registrationInBound(registration);
        }
    }

    private static Map<String, Object> firstOrNull(List<Map<String, Object>> rows) {
        return rows.isEmpty() ? null : rows.get(0);
    }

    /* ── the student's own coursework ─────────────────────────────────────── */

    /** the signed-in PG student's programme courses, their registration and their results for a session/semester */
    @GetMapping("/me")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication authentication,
                             @RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        UUID me = UUID.fromString(authentication.getName());
        Map<String, Object> st = firstOrNull(jdbc.sql("""
                SELECT s.programme_code, s.entry_level, s.entry_mode, g.name AS programme_name
                  FROM people.student s JOIN ref.programme g ON g.code = s.programme_code
                 WHERE s.id = :me AND s.entry_mode = 'POSTGRADUATE'
                """).param("me", me).query().listOfRows());
        if (st == null) {
            throw new DomainRuleViolation("PG_NOT_STUDENT", "Postgraduate coursework is for postgraduate students.",
                    new DomainRuleViolation.Remedy("This does not apply to your programme.", "School of Postgraduate Studies"));
        }
        String prog = String.valueOf(st.get("programme_code"));
        List<Map<String, Object>> courses = jdbc.sql("""
                SELECT id, code, title, units, kind, semester FROM admissions.pg_course
                 WHERE programme_code = :p AND active AND semester = :sem ORDER BY code
                """).param("p", prog).param("sem", semester).query().listOfRows();
        Map<String, Object> reg = firstOrNull(jdbc.sql("""
                SELECT id, mode, state, endorsed_at FROM admissions.pg_registration
                 WHERE student_id = :me AND session = :s AND semester = :sem
                """).param("me", me).param("s", session).param("sem", semester).query().listOfRows());
        List<Map<String, Object>> entries = reg == null ? List.of() : jdbc.sql("""
                SELECT e.id AS entry_id, c.id AS course_id, c.code, c.title, c.units, c.kind,
                       sc.ca, sc.exam, sc.total, sc.grade, sc.points
                  FROM admissions.pg_registration_entry e
                  JOIN admissions.pg_course c ON c.id = e.course_id
                  LEFT JOIN admissions.pg_score sc ON sc.entry_id = e.id
                 WHERE e.registration_id = :r ORDER BY c.code
                """).param("r", reg.get("id")).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("programme", st.get("programme_name"));
        out.put("programmeCode", prog);
        out.put("session", session);
        out.put("semester", semester);
        out.put("courses", courses);
        out.put("registration", reg);
        out.put("entries", entries);
        // V389: the semester's results from both sources, and the registration on the University's engine
        out.put("results", jdbc.sql("""
                SELECT code, title, units, kind, grade, points, total, source FROM admissions.pg_course_results(:me)
                 WHERE session = :s AND semester = :sem ORDER BY code
                """).param("me", me).param("s", session).param("sem", semester).query().listOfRows());
        out.put("engineRegistration", firstOrNull(jdbc.sql("""
                SELECT cr.id, cr.status, count(e.offering_id) AS courses, coalesce(sum(e.units), 0) AS units
                  FROM registration.course_registration cr
                  LEFT JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
                 WHERE cr.student_id = :me AND cr.session = :s AND cr.semester = :sem
                 GROUP BY cr.id, cr.status
                """).param("me", me).param("s", session).param("sem", semester).query().listOfRows()));
        out.put("gpa", jdbc.sql("SELECT admissions.pg_gpa(:me, :s, :sem)").param("me", me).param("s", session).param("sem", semester).query(BigDecimal.class).single());
        out.put("cgpa", jdbc.sql("SELECT admissions.pg_cgpa(:me)").param("me", me).query(BigDecimal.class).single());
        return out;
    }

    /** a compact summary for the PG student's dashboard: coursework standing, latest registration, research stage */
    @GetMapping("/summary")
    @PreAuthorize(STUDENT)
    @Transactional(readOnly = true)
    Map<String, Object> summary(Authentication authentication) {
        UUID me = UUID.fromString(authentication.getName());
        if (!jdbc.sql("SELECT count(*) FROM people.student WHERE id = :me AND entry_mode = 'POSTGRADUATE'")
                .param("me", me).query(Long.class).single().equals(1L)) {
            return Map.of("postgraduate", false);
        }
        BigDecimal cgpa = jdbc.sql("SELECT admissions.pg_cgpa(:me)").param("me", me).query(BigDecimal.class).single();
        // V389: a result of the old coursework or a published result of the School's classes
        boolean scored = Boolean.TRUE.equals(jdbc.sql("SELECT EXISTS (SELECT 1 FROM admissions.pg_course_results(:me))")
                .param("me", me).query(Boolean.class).single());
        // V389: the latest registration on the University's engine, else on the old coursework
        Map<String, Object> reg = firstOrNull(jdbc.sql("""
                SELECT cr.session, cr.semester, st.study_mode AS mode,
                       CASE WHEN cr.status IN ('APPROVED', 'LOCKED') THEN 'ENDORSED' ELSE cr.status END AS state,
                       count(e.offering_id) AS courses, coalesce(sum(e.units), 0) AS units
                  FROM registration.course_registration cr
                  JOIN people.student st ON st.id = cr.student_id
                  JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
                  JOIN catalogue.offering o ON o.id = e.offering_id AND o.stream = 'PG'
                 WHERE cr.student_id = :me
                 GROUP BY cr.id, cr.session, cr.semester, st.study_mode, cr.status
                 ORDER BY cr.session DESC, cr.semester DESC LIMIT 1
                """).param("me", me).query().listOfRows());
        if (reg == null) reg = firstOrNull(jdbc.sql("""
                SELECT r.session, r.semester, r.mode, r.state,
                       (SELECT count(*) FROM admissions.pg_registration_entry e WHERE e.registration_id = r.id) AS courses,
                       (SELECT coalesce(sum(c.units), 0) FROM admissions.pg_registration_entry e
                          JOIN admissions.pg_course c ON c.id = e.course_id WHERE e.registration_id = r.id) AS units
                  FROM admissions.pg_registration r WHERE r.student_id = :me
                 ORDER BY r.session DESC, r.semester DESC LIMIT 1
                """).param("me", me).query().listOfRows());
        Map<String, Object> research = firstOrNull(jdbc.sql("""
                SELECT r.stage, r.topic, r.degree_kind, r.proposal_submitted_at, r.proposal_approved_at,
                       (SELECT s.name FROM admissions.pg_research_supervisor s
                         WHERE s.research_id = r.id AND s.ended_at IS NULL
                         ORDER BY CASE s.role WHEN 'FIRST' THEN 0 WHEN 'SECOND' THEN 1 ELSE 2 END, s.assigned_at LIMIT 1) AS supervisor
                  FROM admissions.pg_research r WHERE r.student_id = :me
                """).param("me", me).query().listOfRows());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("postgraduate", true);
        out.put("cgpa", cgpa);
        out.put("standing", !scored ? "NEW" : cgpa.compareTo(new BigDecimal("2.50")) >= 0 ? "GOOD" : "PROBATION");
        out.put("registration", reg);
        out.put("research", research);
        // the School's own calendar: the session in progress and its open semester, with the registration window
        String pgSession = jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).single();
        out.put("session", pgSession);
        out.put("semester", firstOrNull(jdbc.sql("""
                SELECT number, registration_opens, registration_closes, lectures_from, lectures_to, exams_from, exams_to, results_due, state
                  FROM admissions.pg_semester WHERE session = :s AND state = 'OPEN' ORDER BY number DESC LIMIT 1
                """).param("s", pgSession).query().listOfRows()));
        out.put("supervisors", jdbc.sql("""
                SELECT s.name, s.role, s.is_external, s.assigned_at,
                       CASE WHEN p.id IS NULL THEN NULL ELSE d.name END AS department, p.email
                  FROM admissions.pg_research r JOIN admissions.pg_research_supervisor s ON s.research_id = r.id AND s.ended_at IS NULL
                  LEFT JOIN iam.person p ON p.id = s.person_id
                  LEFT JOIN hrm.staff_record sr ON sr.person_id = p.id
                  LEFT JOIN ref.department d ON d.code = sr.home_department
                 WHERE r.student_id = :me ORDER BY CASE s.role WHEN 'FIRST' THEN 0 WHEN 'SECOND' THEN 1 ELSE 2 END, s.assigned_at
                """).param("me", me).query().listOfRows());
        out.put("researchDates", firstOrNull(jdbc.sql("""
                SELECT r.corrections_due, r.viva_held_at, r.draft_submitted_at, r.final_submitted_at, r.cleared_at, r.awarded_at, r.viva_outcome
                  FROM admissions.pg_research r WHERE r.student_id = :me
                """).param("me", me).query().listOfRows()));
        // V389: the old coursework and the School's classes on the engine together; results from both sources
        out.put("coursework", jdbc.sql("""
                WITH res AS (SELECT * FROM admissions.pg_course_results(:me)),
                legacy AS (SELECT e.id, c.units, c.kind, r.id AS reg, r.state
                             FROM admissions.pg_registration r JOIN admissions.pg_registration_entry e ON e.registration_id = r.id
                             JOIN admissions.pg_course c ON c.id = e.course_id WHERE r.student_id = :me),
                engine AS (SELECT e.offering_id AS id, e.units, coalesce(co.basis, 'Core') AS basis, cr.id AS reg, cr.status
                             FROM registration.course_registration cr
                             JOIN registration.entry e ON e.registration_id = cr.id AND e.status IN ('REGISTERED', 'APPROVED')
                             JOIN catalogue.offering o ON o.id = e.offering_id AND o.stream = 'PG'
                             JOIN people.student st ON st.id = cr.student_id
                             LEFT JOIN catalogue.course_offer co ON co.course_code = o.course_code AND co.programme_code = st.programme_code AND co.level = cr.level
                            WHERE cr.student_id = :me)
                SELECT (SELECT count(*) FROM legacy) + (SELECT count(*) FROM engine) AS courses,
                       (SELECT count(*) FROM res) AS graded,
                       (SELECT count(*) FROM res WHERE grade <> 'F') AS passed,
                       (SELECT count(*) FROM res WHERE grade = 'F') AS failed,
                       (SELECT coalesce(sum(units), 0) FROM legacy WHERE kind <> 'DEFICIENCY') + (SELECT coalesce(sum(units), 0) FROM engine WHERE basis <> 'Deficiency') AS units_registered,
                       (SELECT coalesce(sum(units), 0) FROM res WHERE kind <> 'DEFICIENCY' AND grade <> 'F') AS units_passed,
                       (SELECT count(DISTINCT reg) FROM legacy) + (SELECT count(DISTINCT reg) FROM engine) AS registrations,
                       (SELECT count(DISTINCT reg) FROM legacy WHERE state = 'ENDORSED') + (SELECT count(DISTINCT reg) FROM engine WHERE status IN ('APPROVED', 'LOCKED')) AS endorsed
                """).param("me", me).query().singleRow());
        out.put("graduand", firstOrNull(jdbc.sql("""
                SELECT g.session, g.award, g.cgpa, g.senate_state, g.senate_minute FROM records.graduand g WHERE g.student_id = :me ORDER BY g.session DESC LIMIT 1
                """).param("me", me).query().listOfRows()));
        out.put("clearance", jdbc.sql("SELECT unit, label, state, decided_at FROM clearance.position(:me, 'CONVOCATION') ORDER BY ord")
                .param("me", me).query().listOfRows());
        out.put("status", jdbc.sql("SELECT status FROM people.student WHERE id = :me").param("me", me).query(String.class).single());
        // V389: what the student may do now, worked out by the database from the record — never by the page
        out.put("next", jdbc.sql("""
                SELECT x->>'key' AS key, x->>'state' AS state, x->>'label' AS label, x->>'detail' AS detail, x->>'href' AS href, x->>'action' AS action
                  FROM jsonb_array_elements(admissions.pg_next_steps(:me)) x
                """).param("me", me).query().listOfRows());
        return out;
    }

    public record RegisterIn(@NotBlank String session, @NotNull Integer semester, String mode, List<UUID> courseIds) {
    }

    /** the student registers (or updates) their courses for a session/semester (Policy 7) */
    @PostMapping("/register")
    @PreAuthorize(STUDENT)
    @Transactional
    Map<String, Object> register(Authentication authentication, @Valid @RequestBody RegisterIn body) {
        UUID me = UUID.fromString(authentication.getName());
        String arr = "{" + (body.courseIds() == null ? "" : body.courseIds().stream().map(UUID::toString).collect(Collectors.joining(","))) + "}";
        jdbc.sql("SELECT admissions.pg_register(:me, :s, :sem, :mode, :c::uuid[])")
                .param("me", me).param("s", body.session().trim()).param("sem", body.semester())
                .param("mode", body.mode() == null ? "" : body.mode().trim(), java.sql.Types.VARCHAR)
                .param("c", arr)
                .query().listOfRows();
        return mine(authentication, body.session().trim(), body.semester());
    }

    /* ── V389: the School's classes, in its own session, on the University's engines ── */

    /** the School's classes of a session's semester, with their lecturers, their registered students and their sheets;
     *  a Head of Department reads their own department's courses */
    @GetMapping("/classes")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> classes(@RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester) {
        String s = session == null || session.isBlank() ? jdbc.sql("SELECT admissions.pg_current_session()").query(String.class).single() : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", semester);
        out.put("gate", jdbc.sql("SELECT registration.pg_gate_of(:s, :sem)").param("s", s).param("sem", semester).query(String.class).optional().orElse(null));
        out.put("classes", jdbc.sql("""
                SELECT o.id, o.course_code, coalesce(o.title, c.title) AS title, coalesce(o.units, c.units) AS units, c.dept_code, d.name AS department,
                       nullif(btrim(coalesce(lp.surname, '') || ', ' || coalesce(lp.given_names, '')), ',') AS lecturer,
                       (SELECT count(*) FROM registration.entry e JOIN registration.course_registration r ON r.id = e.registration_id
                         WHERE e.offering_id = o.id AND e.status IN ('REGISTERED', 'APPROVED') AND r.status IN ('SUBMITTED', 'APPROVED', 'LOCKED')) AS registered,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id ORDER BY sh.due_on DESC NULLS LAST LIMIT 1) AS sheet_stage
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                  LEFT JOIN iam.person lp ON lp.id = o.lecturer_id
                 WHERE o.stream = 'PG' AND o.session = :s AND o.semester = :sem AND (:dept::text IS NULL OR c.dept_code = :dept)
                 ORDER BY o.course_code
                """).param("s", s).param("sem", semester).param("dept", hodDept(), java.sql.Types.VARCHAR).query().listOfRows());
        out.put("unmapped", jdbc.sql("SELECT programme_code, code, title FROM admissions.pg_course_unmapped WHERE active ORDER BY programme_code, code LIMIT 200").query().listOfRows());
        return out;
    }

    public record OpenIn(@NotBlank String session, @NotNull Integer semester) {
    }

    /** every class the semester needs, opened at once in the School's session */
    @PostMapping("/classes/open")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> openClasses(@Valid @RequestBody OpenIn body) {
        Integer n = jdbc.sql("SELECT catalogue.pg_open_classes(:s, :sem)").param("s", body.session().trim()).param("sem", body.semester()).query(Integer.class).single();
        Map<String, Object> out = classes(body.session().trim(), body.semester());
        out.put("opened", n);
        return out;
    }

    public record ClassIn(@NotBlank @Size(max = 20) String course, @NotBlank String session, @NotNull Integer semester) {
    }

    /** one class added for a course of the pool */
    @PostMapping("/classes")
    @PreAuthorize(SCHOOL)
    @Transactional
    Map<String, Object> addClass(@Valid @RequestBody ClassIn body) {
        jdbc.sql("SELECT catalogue.pg_add_class(:c, :s, :sem)").param("c", body.course().trim()).param("s", body.session().trim()).param("sem", body.semester()).query().listOfRows();
        return classes(body.session().trim(), body.semester());
    }

    /* ── the department / School desk ─────────────────────────────────────── */

    /** the courses of a programme (desk) — V471: read from the programme's structure on the University's one course pool
     *  (catalogue.course_offer), the list the registration menu and the results read; a course added here, or uploaded, is
     *  bound there (V389), and one bound on the Programme Structure shows here the same */
    @GetMapping("/courses")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam String programme) {
        programmeInBound(programme);
        return jdbc.sql("""
                SELECT c.id, c.code, c.title, coalesce(co.units, c.units) AS units, upper(co.basis) AS kind, c.semester, co.level,
                       (c.state <> 'ENDED') AS active
                  FROM catalogue.course_offer co JOIN catalogue.course c ON c.code = co.course_code
                 WHERE co.programme_code = :p ORDER BY co.level, c.semester, c.code
                """).param("p", programme.trim()).query().listOfRows();
    }

    /** every postgraduate programme's courses, with the programme — the School's whole structure for the desk (V471: the pool's) */
    @GetMapping("/courses/all")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> allCourses() {
        return jdbc.sql("""
                SELECT c.id, co.programme_code, g.name AS programme_name, f.name AS faculty_name,
                       c.code, c.title, coalesce(co.units, c.units) AS units, upper(co.basis) AS kind, c.semester, co.level, (c.state <> 'ENDED') AS active
                  FROM catalogue.course_offer co
                  JOIN catalogue.course c ON c.code = co.course_code
                  JOIN ref.programme g ON g.code = co.programme_code AND g.category = 'POST GRADUATE'
                  LEFT JOIN ref.faculty f ON f.code = g.faculty_code
                 WHERE (:dept::text IS NULL OR g.dept_code = :dept)
                 ORDER BY g.name, co.level, c.semester, c.code
                """).param("dept", hodDept(), java.sql.Types.VARCHAR).query().listOfRows();
    }

    public record CourseIn(@NotBlank String programmeCode, @NotBlank @Size(max = 20) String code,
                           @NotBlank @Size(max = 200) String title, @NotNull Integer units,
                           String kind, Integer semester) {
    }

    /** add (or update) a course on a programme (desk) */
    @PostMapping("/courses")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> addCourse(@Valid @RequestBody CourseIn body) {
        programmeInBound(body.programmeCode());
        if (!jdbc.sql("SELECT count(*) FROM ref.programme WHERE code = :p AND category = 'POST GRADUATE'")
                .param("p", body.programmeCode().trim()).query(Long.class).single().equals(1L)) {
            throw new NotFound("postgraduate programme", body.programmeCode());
        }
        String kind = body.kind() == null || body.kind().isBlank() ? "CORE" : body.kind().trim().toUpperCase();
        int sem = body.semester() == null ? 1 : body.semester();
        jdbc.sql("""
                INSERT INTO admissions.pg_course (programme_code, code, title, units, kind, semester)
                VALUES (:p, :c, :t, :u, :k, :sem)
                ON CONFLICT (programme_code, code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units,
                    kind = EXCLUDED.kind, semester = EXCLUDED.semester, active = true
                """)
                .param("p", body.programmeCode().trim()).param("c", body.code().trim().toUpperCase())
                .param("t", body.title().trim()).param("u", body.units()).param("k", kind).param("sem", sem)
                .update();
        return Map.of("ok", true);
    }

    public record CoursesIn(@NotNull List<Map<String, Object>> rows) {
    }

    /** bulk-upload the postgraduate course catalogue from a spreadsheet (desk). Each row names the
     *  programme (its code or its name), the course code, the title, units, kind and semester; it upserts
     *  on (programme, code), so a re-upload updates rather than duplicates. */
    @PostMapping("/courses/import")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> importCourses(@Valid @RequestBody CoursesIn body) {
        if (body.rows() == null || body.rows().isEmpty()) {
            throw new DomainRuleViolation("PG_COURSE_ROWS", "The file has no rows to read.",
                    new DomainRuleViolation.Remedy("Download the template, fill it and upload it.", "Postgraduate School"));
        }
        int created = 0, updated = 0, noProg = 0, skipped = 0, outside = 0;
        String dept = hodDept();
        String firstError = null;
        for (Map<String, Object> r : body.rows()) {
            try {
                String progRaw = str(r.get("programme"));
                String code = str(r.get("code")).toUpperCase();
                String title = str(r.get("title"));
                if (progRaw.isBlank() || code.isBlank() || title.isBlank()) { skipped++; continue; }
                String prog = jdbc.sql("""
                        SELECT code FROM ref.programme
                         WHERE category = 'POST GRADUATE' AND (upper(code) = upper(:p) OR upper(name) = upper(:p))
                         ORDER BY archived, code LIMIT 1
                        """).param("p", progRaw).query(String.class).optional().orElse(null);
                if (prog == null) { noProg++; continue; }
                // a Head of Department loads their own department's programmes only; another department's rows are skipped, not written
                if (dept != null && !dept.equalsIgnoreCase(jdbc.sql("SELECT dept_code FROM ref.programme WHERE code = :p").param("p", prog)
                        .query(String.class).optional().orElse(""))) { outside++; continue; }
                int units = parseFirstInt(str(r.get("units")), 3);
                if (units < 0 || units > 12) { units = 3; }
                String kind = str(r.get("kind")).toUpperCase();
                if (!List.of("CORE", "ELECTIVE", "DEFICIENCY", "RESEARCH").contains(kind)) { kind = "CORE"; }
                String semRaw = str(r.get("semester")).toLowerCase();
                int sem = semRaw.startsWith("2") || semRaw.startsWith("s") ? 2 : 1;
                boolean exists = jdbc.sql("SELECT count(*) FROM admissions.pg_course WHERE programme_code = :p AND code = :c")
                        .param("p", prog).param("c", code).query(Long.class).single() == 1L;
                jdbc.sql("""
                        INSERT INTO admissions.pg_course (programme_code, code, title, units, kind, semester)
                        VALUES (:p, :c, :t, :u, :k, :sem)
                        ON CONFLICT (programme_code, code) DO UPDATE SET title = EXCLUDED.title, units = EXCLUDED.units,
                            kind = EXCLUDED.kind, semester = EXCLUDED.semester, active = true
                        """).param("p", prog).param("c", code).param("t", title).param("u", units).param("k", kind).param("sem", sem).update();
                if (exists) { updated++; } else { created++; }
            } catch (RuntimeException e) {
                skipped++;
                if (firstError == null) { firstError = e.getMessage(); }
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", body.rows().size());
        out.put("created", created);
        out.put("updated", updated);
        out.put("no_programme", noProg);
        out.put("outside_department", outside);
        out.put("skipped", skipped);
        out.put("first_error", firstError);
        return out;
    }

    private static String str(Object o) {
        return o == null ? "" : o.toString().trim();
    }

    private static int parseFirstInt(String s, int def) {
        java.util.regex.Matcher m = java.util.regex.Pattern.compile("\\d+").matcher(s);
        return m.find() ? Integer.parseInt(m.group()) : def;
    }

    /** the registrations for a session, optionally by programme (desk: to endorse and to enter scores) */
    @GetMapping("/registrations")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> registrations(@RequestParam String session, @RequestParam(defaultValue = "1") int semester,
                                            @RequestParam(required = false) String programme) {
        return jdbc.sql("""
                SELECT r.id, r.session, r.semester, r.mode, r.state, r.endorsed_at,
                       s.surname, s.other_names, s.matric_no, s.admission_no,
                       g.name AS programme_name, s.programme_code,
                       (SELECT count(*) FROM admissions.pg_registration_entry e WHERE e.registration_id = r.id) AS courses,
                       admissions.pg_gpa(s.id, r.session, r.semester) AS gpa
                  FROM admissions.pg_registration r
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme g ON g.code = s.programme_code
                 WHERE r.session = :s AND r.semester = :sem
                   AND (:prog::text IS NULL OR s.programme_code = :prog)
                   AND (:dept::text IS NULL OR g.dept_code = :dept)
                 ORDER BY s.surname, s.other_names
                """)
                .param("s", session.trim()).param("sem", semester).param("dept", hodDept(), java.sql.Types.VARCHAR)
                .param("prog", programme == null || programme.isBlank() ? null : programme.trim(), java.sql.Types.VARCHAR)
                .query().listOfRows();
    }

    /** one registration's courses and scores (desk) */
    @GetMapping("/registrations/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> registration(@PathVariable UUID id) {
        registrationInBound(id);
        Map<String, Object> r = firstOrNull(jdbc.sql("""
                SELECT r.id, r.session, r.semester, r.mode, r.state, s.surname, s.other_names,
                       s.matric_no, s.admission_no, g.name AS programme_name
                  FROM admissions.pg_registration r
                  JOIN people.student s ON s.id = r.student_id
                  JOIN ref.programme g ON g.code = s.programme_code
                 WHERE r.id = :id
                """).param("id", id).query().listOfRows());
        if (r == null) {
            throw new NotFound("registration", id);
        }
        List<Map<String, Object>> entries = jdbc.sql("""
                SELECT e.id AS entry_id, c.code, c.title, c.units, c.kind,
                       sc.ca, sc.exam, sc.total, sc.grade, sc.points
                  FROM admissions.pg_registration_entry e
                  JOIN admissions.pg_course c ON c.id = e.course_id
                  LEFT JOIN admissions.pg_score sc ON sc.entry_id = e.id
                 WHERE e.registration_id = :id ORDER BY c.code
                """).param("id", id).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>(r);
        out.put("name", r.get("surname") + ", " + r.get("other_names"));
        out.put("entries", entries);
        return out;
    }

    /** endorse a registration (the Head of Department / School) */
    @PostMapping("/registrations/{id}/endorse")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> endorse(@PathVariable UUID id, Authentication authentication) {
        registrationInBound(id);
        UUID by;
        try {
            by = UUID.fromString(authentication.getName());
        } catch (IllegalArgumentException notUuid) {
            by = null;
        }
        jdbc.sql("UPDATE admissions.pg_registration SET state = 'ENDORSED', endorsed_by = :by, endorsed_at = now(), updated_at = now() WHERE id = :id")
                .param("by", by).param("id", id).update();
        jdbc.sql("SELECT admissions.tell_pg_endorsed(:id)").param("id", id).query().listOfRows();   // V360: the student told
        return registration(id);
    }

    public record ScoreIn(@NotNull UUID entryId, BigDecimal ca, BigDecimal exam) {
    }

    /** record (or revise) a score; the grade is computed from the total (Policy 16) */
    @PostMapping("/score")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> score(@Valid @RequestBody ScoreIn body, Authentication authentication) {
        entryInBound(body.entryId());
        UUID by;
        try {
            by = UUID.fromString(authentication.getName());
        } catch (IllegalArgumentException notUuid) {
            by = null;
        }
        jdbc.sql("SELECT admissions.pg_record_score(:e, :ca, :ex, :by)")
                .param("e", body.entryId()).param("ca", body.ca()).param("ex", body.exam()).param("by", by)
                .query().listOfRows();
        // V360: the student told a score is recorded in the course (once a day for it; the score is on the portal, not in the message)
        boolean told = Boolean.TRUE.equals(jdbc.sql("SELECT admissions.tell_pg_scored(:e)").param("e", body.entryId()).query(Boolean.class).single());
        return Map.of("ok", true, "told", told);
    }
}
