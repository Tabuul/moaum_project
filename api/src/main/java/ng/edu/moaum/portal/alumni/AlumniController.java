package ng.edu.moaum.portal.alumni;

import java.sql.Types;
import java.util.List;
import java.util.Map;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/** The alumni register — students Senate has graduated. */
@RestController
class AlumniController {

    private static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records','OFFICE_vc','OFFICE_dvc','OFFICE_audit','OFFICE_deputyaudit','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    AlumniController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    @GetMapping("/api/v1/alumni")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> alumni(@RequestParam(required = false) String q, @RequestParam(required = false) String faculty,
                               @RequestParam(required = false) String session) {
        String like = q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%";
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT s.surname || ', ' || s.other_names AS name, s.matric_no,
                       p.name AS programme, f.name AS faculty, g.session, g.award, g.cgpa,
                       policy.class_of(g.cgpa) AS class
                  FROM records.graduand g
                  JOIN people.student s ON s.id = g.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.faculty f ON f.code = p.faculty_code
                 WHERE g.senate_state = 'APPROVED'
                   AND (:like::text IS NULL OR lower(s.surname || ' ' || s.other_names) LIKE :like OR lower(coalesce(s.matric_no, '')) LIKE :like)
                   AND (:fac::text IS NULL OR f.name = :fac)
                   AND (:ses::text IS NULL OR g.session = :ses)
                 ORDER BY g.session DESC, s.surname, s.other_names
                """)
                .param("like", like, Types.VARCHAR).param("fac", faculty == null || faculty.isBlank() ? null : faculty, Types.VARCHAR)
                .param("ses", session == null || session.isBlank() ? null : session, Types.VARCHAR)
                .query().listOfRows();
        Map<String, Object> tiles = jdbc.sql("""
                SELECT count(*) AS total, count(DISTINCT g.session) AS sessions,
                       count(*) FILTER (WHERE g.session = (SELECT max(session) FROM records.graduand WHERE senate_state = 'APPROVED')) AS latest_cohort
                  FROM records.graduand g WHERE g.senate_state = 'APPROVED'
                """).query().singleRow();
        List<Map<String, Object>> sessions = jdbc.sql("SELECT DISTINCT session FROM records.graduand WHERE senate_state = 'APPROVED' ORDER BY session DESC").query().listOfRows();
        return Map.of("rows", rows, "tiles", tiles, "sessions", sessions);
    }
}
