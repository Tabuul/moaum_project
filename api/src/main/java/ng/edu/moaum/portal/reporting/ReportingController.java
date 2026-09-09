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
                       count(*) FILTER (WHERE sh.stage = 'PUBLISHED') AS published,
                       count(*) FILTER (WHERE sh.stage <> 'PUBLISHED') AS in_progress
                  FROM assessment.score_sheet sh
                  JOIN catalogue.offering o ON o.id = sh.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code
                  JOIN ref.department d ON d.code = c.dept_code
                  JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE o.session = :s AND o.semester = :sem
                 GROUP BY f.code, f.name ORDER BY f.name
                """).param("s", s).param("sem", semester).query().listOfRows();

        List<Map<String, Object>> collection = jdbc.sql("SELECT * FROM finance.collection_by_faculty(:s)").param("s", s).query().listOfRows();

        Map<String, Object> studentsOut = new LinkedHashMap<>();
        studentsOut.put("total", students);
        studentsOut.put("byFaculty", byFaculty);
        studentsOut.put("byLevel", byLevel);

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("semester", semester);
        out.put("students", studentsOut);
        out.put("results", results);
        out.put("collection", collection);
        return out;
    }
}
