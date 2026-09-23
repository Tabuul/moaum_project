package ng.edu.moaum.portal.pgadmissions;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Secretary of the School of Postgraduate Studies' four desks, read off the registers already kept:
 * registration and matriculation (Policy 7–8), course examinations (Policy 17), thesis clearance
 * (Policy 31–32) and the award of degrees to Senate (Policy 33–34). Each is a view; the acts that move
 * a record live on the desks that own them (registration endorsement, the research lifecycle).
 */
@RestController
@RequestMapping("/api/v1/pg/secretary")
class PgSecretaryController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_pgsecretary','OFFICE_pgschool','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";

    private final JdbcClient jdbc;

    PgSecretaryController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** registration & matriculation: who is yet to register, who has, the part-time share, and who lapsed */
    @GetMapping("/registration")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> registration(@RequestParam String session) {
        Map<String, Object> counts = jdbc.sql("""
                SELECT
                  (SELECT count(*) FROM people.student s
                    WHERE s.entry_mode = 'POSTGRADUATE' AND s.status = 'ACTIVE'
                      AND NOT EXISTS (SELECT 1 FROM admissions.pg_registration r
                                       WHERE r.student_id = s.id AND r.session = :s AND r.state IN ('SUBMITTED','ENDORSED'))) AS to_register,
                  (SELECT count(DISTINCT r.student_id) FROM admissions.pg_registration r
                    WHERE r.session = :s AND r.state IN ('SUBMITTED','ENDORSED')) AS registered,
                  (SELECT count(DISTINCT r.student_id) FROM admissions.pg_registration r
                    WHERE r.session = :s AND r.state IN ('SUBMITTED','ENDORSED') AND r.mode = 'PART_TIME') AS part_time,
                  (SELECT count(*) FROM people.student s
                    WHERE s.entry_mode = 'POSTGRADUATE' AND s.status = 'ACTIVE'
                      AND NOT EXISTS (SELECT 1 FROM admissions.pg_registration r
                                       WHERE r.student_id = s.id AND r.session = :s AND r.state IN ('SUBMITTED','ENDORSED'))
                      AND EXISTS (SELECT 1 FROM admissions.pg_registration r0
                                   WHERE r0.student_id = s.id AND r0.session < :s AND r0.state IN ('SUBMITTED','ENDORSED'))) AS lapsed
                """).param("s", session).query().singleRow();
        /* the students admitted this session — their fee, mode and matriculation standing */
        List<Map<String, Object>> fresh = jdbc.sql("""
                SELECT st.id, st.surname, st.other_names, st.matric_no, st.admission_no, st.matriculated_at,
                       g.name AS programme_name, g.pg_award, d.name AS department_name,
                       (SELECT r.mode FROM admissions.pg_registration r WHERE r.student_id = st.id AND r.session = :s
                         ORDER BY r.semester LIMIT 1) AS mode,
                       EXISTS (SELECT 1 FROM admissions.pg_application a
                                WHERE a.student_id = st.id AND a.acceptance_confirmed_at IS NOT NULL) AS acceptance_paid,
                       EXISTS (SELECT 1 FROM admissions.pg_registration r
                                WHERE r.student_id = st.id AND r.session = :s AND r.state IN ('SUBMITTED','ENDORSED')) AS registered
                  FROM people.student st
                  JOIN ref.programme g ON g.code = st.programme_code
                  JOIN ref.department d ON d.code = g.dept_code
                 WHERE st.entry_mode = 'POSTGRADUATE' AND st.entry_session = :s
                 ORDER BY st.surname, st.other_names
                """).param("s", session).query().listOfRows();
        /* every registration this session, by semester — renewed or not */
        List<Map<String, Object>> renewals = jdbc.sql("""
                SELECT r.id, r.semester, r.mode, r.state, r.updated_at,
                       st.surname, st.other_names, st.matric_no, g.name AS programme_name, g.pg_award,
                       (SELECT count(*) FROM admissions.pg_registration_entry e WHERE e.registration_id = r.id) AS courses
                  FROM admissions.pg_registration r
                  JOIN people.student st ON st.id = r.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE r.session = :s
                 ORDER BY r.semester, st.surname, st.other_names
                """).param("s", session).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("counts", counts);
        out.put("fresh", fresh);
        out.put("renewals", renewals);
        return out;
    }

    /** course examinations: the courses sat this semester and where their results stand */
    @GetMapping("/examinations")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> examinations(@RequestParam String session, @RequestParam(defaultValue = "1") int semester) {
        List<Map<String, Object>> courses = jdbc.sql("""
                SELECT c.id, c.code, c.title, c.units, c.kind, g.name AS programme_name, d.name AS department_name,
                       count(e.id) AS candidates,
                       count(sc.id) AS scored
                  FROM admissions.pg_registration_entry e
                  JOIN admissions.pg_registration r ON r.id = e.registration_id
                  JOIN admissions.pg_course c ON c.id = e.course_id
                  JOIN ref.programme g ON g.code = c.programme_code
                  JOIN ref.department d ON d.code = g.dept_code
                  LEFT JOIN admissions.pg_score sc ON sc.entry_id = e.id
                 WHERE r.session = :s AND r.semester = :sem AND r.state = 'ENDORSED'
                 GROUP BY c.id, c.code, c.title, c.units, c.kind, g.name, d.name
                 ORDER BY d.name, c.code
                """).param("s", session).param("sem", semester).query().listOfRows();
        long recorded = courses.stream().filter(c -> ((Number) c.get("candidates")).longValue() > 0
                && ((Number) c.get("scored")).longValue() >= ((Number) c.get("candidates")).longValue()).count();
        long candidates = courses.stream().mapToLong(c -> ((Number) c.get("candidates")).longValue()).sum();
        Map<String, Object> counts = new LinkedHashMap<>();
        counts.put("courses", courses.size());
        counts.put("recorded", recorded);
        counts.put("awaited", courses.size() - recorded);
        counts.put("candidates", candidates);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("semester", semester);
        out.put("counts", counts);
        out.put("courses", courses);
        return out;
    }

    /** thesis clearance: the final versions awaiting the Secretary's clearance before binding, and those cleared */
    @GetMapping("/clearance")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> clearance() {
        List<Map<String, Object>> awaiting = jdbc.sql("""
                SELECT rs.id, rs.degree_kind, rs.topic, rs.final_submitted_at, rs.plagiarism_pct, rs.viva_grade, rs.viva_outcome,
                       st.surname, st.other_names, st.matric_no, g.name AS programme_name, g.pg_award
                  FROM admissions.pg_research rs
                  JOIN people.student st ON st.id = rs.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE rs.stage = 'FINAL_SUBMITTED'
                 ORDER BY rs.final_submitted_at NULLS LAST, st.surname
                """).query().listOfRows();
        List<Map<String, Object>> cleared = jdbc.sql("""
                SELECT rs.id, rs.degree_kind, rs.topic, rs.cleared_at, rs.stage,
                       st.surname, st.other_names, st.matric_no, g.name AS programme_name, g.pg_award
                  FROM admissions.pg_research rs
                  JOIN people.student st ON st.id = rs.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE rs.cleared_at IS NOT NULL
                 ORDER BY rs.cleared_at DESC LIMIT 50
                """).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("awaiting", awaiting);
        out.put("cleared", cleared);
        return out;
    }

    /** the award of degrees: computed results with the Board for Senate, and those Senate has awarded this session */
    @GetMapping("/senate")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> senate(@RequestParam String session) {
        int y1 = Integer.parseInt(session.substring(0, 4));
        List<Map<String, Object>> toSenate = jdbc.sql("""
                SELECT rs.id, rs.degree_kind, rs.topic, rs.award_recommended_at, rs.viva_grade, rs.viva_outcome,
                       admissions.pg_cgpa(st.id) AS cgpa,
                       st.surname, st.other_names, st.matric_no, g.name AS programme_name, g.pg_award
                  FROM admissions.pg_research rs
                  JOIN people.student st ON st.id = rs.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE rs.stage = 'AWARD_RECOMMENDED'
                 ORDER BY rs.award_recommended_at NULLS LAST, st.surname
                """).query().listOfRows();
        List<Map<String, Object>> awarded = jdbc.sql("""
                SELECT rs.id, rs.degree_kind, rs.awarded_at,
                       st.surname, st.other_names, st.matric_no, g.name AS programme_name, g.pg_award
                  FROM admissions.pg_research rs
                  JOIN people.student st ON st.id = rs.student_id
                  JOIN ref.programme g ON g.code = st.programme_code
                 WHERE rs.stage = 'AWARDED' AND rs.awarded_at >= make_date(:y1, 1, 1) AND rs.awarded_at < make_date(:y2, 1, 1)
                 ORDER BY rs.awarded_at DESC
                """).param("y1", y1).param("y2", y1 + 2).query().listOfRows();
        Map<String, Object> counts = jdbc.sql("""
                SELECT
                  (SELECT count(*) FROM admissions.pg_score sc
                     JOIN admissions.pg_registration_entry e ON e.id = sc.entry_id
                     JOIN admissions.pg_registration r ON r.id = e.registration_id
                    WHERE r.session = :s) AS coursework_results,
                  (SELECT count(*) FROM admissions.pg_registration_entry e
                     JOIN admissions.pg_registration r ON r.id = e.registration_id
                    WHERE r.session = :s AND r.state = 'ENDORSED'
                      AND NOT EXISTS (SELECT 1 FROM admissions.pg_score sc WHERE sc.entry_id = e.id)) AS pending_computation
                """).param("s", session).query().singleRow();
        Map<String, Object> c = new LinkedHashMap<>(counts);
        c.put("to_senate", toSenate.size());
        c.put("awarded", awarded.size());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", session);
        out.put("counts", c);
        out.put("toSenate", toSenate);
        out.put("awarded", awarded);
        return out;
    }
}
