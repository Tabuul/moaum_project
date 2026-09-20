package ng.edu.moaum.portal.reporting;

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

/** Institutional overview and reporting (RBI): read models over the record. */
@RestController
@RequestMapping("/api/v1/reporting")
class ReportingController {

    private static final String MANAGEMENT = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_vc','OFFICE_dvc','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_audit','OFFICE_bursar')";

    private final JdbcClient jdbc;

    ReportingController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the session so far, in figures: students, result sets and collections */
    @GetMapping("/overview")
    @PreAuthorize(MANAGEMENT)
    @Transactional(readOnly = true)
    Map<String, Object> overview(@RequestParam(required = false) String session, @RequestParam(defaultValue = "1") int semester) {
        String s = session == null || session.isBlank()
                ? jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse("2026/2027")
                : session;

        List<Map<String, Object>> byFaculty = jdbc.sql("""
                SELECT f.code, f.name, count(*) AS students
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE st.status = 'ACTIVE'
                 GROUP BY f.code, f.name ORDER BY f.name
                """).query().listOfRows();
        List<Map<String, Object>> byLevel = jdbc.sql("""
                SELECT current_level AS level, count(*) AS students FROM people.student WHERE status = 'ACTIVE'
                 GROUP BY current_level ORDER BY current_level
                """).query().listOfRows();
        int students = jdbc.sql("SELECT count(*) FROM people.student WHERE status = 'ACTIVE'").query(Integer.class).single();

        List<Map<String, Object>> results = jdbc.sql("""
                SELECT f.code, f.name, count(*) AS expected,
                       count(*) FILTER (WHERE sh.stage <> 'ENTRY') AS submitted,
                       count(*) FILTER (WHERE sh.stage = 'PUBLISHED') AS approved,
                       count(*) FILTER (WHERE sh.stage = 'PUBLISHED') AS published,
                       count(*) FILTER (WHERE sh.stage <> 'PUBLISHED') AS in_progress
                  FROM assessment.score_sheet sh
                  JOIN catalogue.offering o ON o.id = sh.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE o.session = :s AND o.semester = :sem
                   AND coalesce((SELECT es.kind FROM assessment.exam_session es WHERE es.id = sh.exam_session_id), 'MAIN') = 'MAIN'
                 GROUP BY f.code, f.name ORDER BY f.name
                """).param("s", s).param("sem", semester).query().listOfRows();

        List<Map<String, Object>> collection = jdbc.sql("SELECT * FROM finance.collection_by_faculty(:s)").param("s", s).query().listOfRows();

        /* the grade spread over every published, graded entry — the band is computed
           from the marks (I-RES bands), the same way the transcript computes it */
        List<Map<String, Object>> grades = jdbc.sql("""
                WITH latest AS (
                    SELECT DISTINCT ON (sc.sheet_id, sc.student_id) sc.ca, sc.exam, sc.outcome
                      FROM assessment.score sc
                      JOIN assessment.score_sheet sh ON sh.id = sc.sheet_id
                      JOIN catalogue.offering o ON o.id = sh.offering_id
                     WHERE o.session = :s AND o.semester = :sem AND sh.stage = 'PUBLISHED'
                       AND coalesce((SELECT es.kind FROM assessment.exam_session es WHERE es.id = sh.exam_session_id), 'MAIN') = 'MAIN'
                     ORDER BY sc.sheet_id, sc.student_id, sc.version DESC)
                SELECT CASE WHEN ca + exam >= 70 THEN 'A' WHEN ca + exam >= 60 THEN 'B'
                            WHEN ca + exam >= 50 THEN 'C' WHEN ca + exam >= 45 THEN 'D'
                            WHEN ca + exam >= 40 THEN 'E' ELSE 'F' END AS grade,
                       count(*) AS count
                  FROM latest WHERE outcome = 'GRADED'
                 GROUP BY 1
                """).param("s", s).param("sem", semester).query().listOfRows();

        /* the semester week by week: cumulative sets the lecturer has submitted and the
           number past Senate, bucketed from the first submission of the session */
        List<Map<String, Object>> weeks = jdbc.sql("""
                WITH sh AS (
                    SELECT s.submitted_at, s.published_at
                      FROM assessment.score_sheet s
                      JOIN catalogue.offering o ON o.id = s.offering_id
                     WHERE o.session = :s AND o.semester = :sem
                       AND coalesce((SELECT es.kind FROM assessment.exam_session es WHERE es.id = s.exam_session_id), 'MAIN') = 'MAIN'),
                b AS (
                    SELECT min(submitted_at) AS t0,
                           greatest(coalesce(max(published_at), max(submitted_at)), now()) AS t1
                      FROM sh WHERE submitted_at IS NOT NULL),
                wk AS (
                    SELECT gs AS week, b.t0
                      FROM b, generate_series(0, LEAST(25, GREATEST(0,
                             floor(extract(epoch FROM (b.t1 - b.t0)) / 604800)::int))) AS gs
                     WHERE b.t0 IS NOT NULL)
                SELECT wk.week AS week, 'Wk ' || (wk.week + 1) AS label,
                       (SELECT count(*) FROM sh WHERE sh.submitted_at IS NOT NULL
                          AND sh.submitted_at <= wk.t0 + make_interval(weeks => (wk.week + 1)::int)) AS submitted,
                       (SELECT count(*) FROM sh WHERE sh.published_at IS NOT NULL
                          AND sh.published_at <= wk.t0 + make_interval(weeks => (wk.week + 1)::int)) AS approved
                  FROM wk ORDER BY wk.week
                """).param("s", s).param("sem", semester).query().listOfRows();

        int faculties = jdbc.sql("SELECT count(*) FROM ref.faculty").query(Integer.class).single();
        int departments = jdbc.sql("SELECT count(*) FROM ref.department").query(Integer.class).single();

        Map<String, Object> studentsOut = new LinkedHashMap<>();
        studentsOut.put("total", students);
        studentsOut.put("byFaculty", byFaculty);
        studentsOut.put("byLevel", byLevel);

        Map<String, Object> uni = new LinkedHashMap<>();
        uni.put("students", students);
        uni.put("faculties", faculties);
        uni.put("departments", departments);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", semester);
        out.put("uni", uni);
        out.put("students", studentsOut);
        out.put("results", results);
        out.put("grades", grades);
        out.put("weeks", weeks);
        out.put("collection", collection);
        return out;
    }
}
