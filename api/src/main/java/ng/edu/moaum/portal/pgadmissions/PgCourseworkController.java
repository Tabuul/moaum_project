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

import org.springframework.jdbc.core.simple.JdbcClient;
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

    private final JdbcClient jdbc;

    PgCourseworkController(JdbcClient jdbc) {
        this.jdbc = jdbc;
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
        boolean scored = Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM admissions.pg_registration r
                    JOIN admissions.pg_registration_entry e ON e.registration_id = r.id
                    JOIN admissions.pg_score s ON s.entry_id = e.id WHERE r.student_id = :me)
                """).param("me", me).query(Boolean.class).single());
        Map<String, Object> reg = firstOrNull(jdbc.sql("""
                SELECT r.session, r.semester, r.mode, r.state,
                       (SELECT count(*) FROM admissions.pg_registration_entry e WHERE e.registration_id = r.id) AS courses
                  FROM admissions.pg_registration r WHERE r.student_id = :me
                 ORDER BY r.session DESC, r.semester DESC LIMIT 1
                """).param("me", me).query().listOfRows());
        Map<String, Object> research = firstOrNull(jdbc.sql("""
                SELECT stage, topic, degree_kind FROM admissions.pg_research WHERE student_id = :me
                """).param("me", me).query().listOfRows());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("postgraduate", true);
        out.put("cgpa", cgpa);
        out.put("standing", !scored ? "NEW" : cgpa.compareTo(new BigDecimal("2.50")) >= 0 ? "GOOD" : "PROBATION");
        out.put("registration", reg);
        out.put("research", research);
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

    /* ── the department / School desk ─────────────────────────────────────── */

    /** the courses of a programme (desk) */
    @GetMapping("/courses")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@RequestParam String programme) {
        return jdbc.sql("""
                SELECT id, code, title, units, kind, semester, active FROM admissions.pg_course
                 WHERE programme_code = :p ORDER BY semester, code
                """).param("p", programme.trim()).query().listOfRows();
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
                 ORDER BY s.surname, s.other_names
                """)
                .param("s", session.trim()).param("sem", semester)
                .param("prog", programme == null || programme.isBlank() ? null : programme.trim(), java.sql.Types.VARCHAR)
                .query().listOfRows();
    }

    /** one registration's courses and scores (desk) */
    @GetMapping("/registrations/{id}")
    @PreAuthorize(DESK)
    @Transactional(readOnly = true)
    Map<String, Object> registration(@PathVariable UUID id) {
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
        UUID by;
        try {
            by = UUID.fromString(authentication.getName());
        } catch (IllegalArgumentException notUuid) {
            by = null;
        }
        jdbc.sql("UPDATE admissions.pg_registration SET state = 'ENDORSED', endorsed_by = :by, endorsed_at = now(), updated_at = now() WHERE id = :id")
                .param("by", by).param("id", id).update();
        return registration(id);
    }

    public record ScoreIn(@NotNull UUID entryId, BigDecimal ca, BigDecimal exam) {
    }

    /** record (or revise) a score; the grade is computed from the total (Policy 16) */
    @PostMapping("/score")
    @PreAuthorize(DESK)
    @Transactional
    Map<String, Object> score(@Valid @RequestBody ScoreIn body, Authentication authentication) {
        UUID by;
        try {
            by = UUID.fromString(authentication.getName());
        } catch (IllegalArgumentException notUuid) {
            by = null;
        }
        jdbc.sql("SELECT admissions.pg_record_score(:e, :ca, :ex, :by)")
                .param("e", body.entryId()).param("ca", body.ca()).param("ex", body.exam()).param("by", by)
                .query().listOfRows();
        return Map.of("ok", true);
    }
}
