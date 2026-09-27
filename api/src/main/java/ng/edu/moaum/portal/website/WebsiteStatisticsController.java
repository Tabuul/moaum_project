package ng.edu.moaum.portal.website;

import java.text.NumberFormat;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.concurrent.TimeUnit;

import org.springframework.http.CacheControl;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * The University's figures for its public website — faculties and colleges,
 * academic departments, courses of study, degree programme types, enrolled
 * students, academic and support staff — read live from the tables that own
 * them, so the website's counters follow the register, the catalogue and the
 * nominal roll without anyone retyping a number.
 * <p>
 * Unauthenticated and cross-origin (see SecurityConfig): the website fetches it
 * straight from the browser. It carries no personal data — only counts — and is
 * cached for five minutes at the edge and in the browser. {@code figures} are
 * the exact integers; {@code display} the same figures formatted with thousands
 * separators for a counter that shows them as they are.
 */
@RestController
@RequestMapping("/api/v1/public")
class WebsiteStatisticsController {

    private final JdbcClient jdbc;

    WebsiteStatisticsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** what the figures count — published beside them so the website's caption can say so */
    private static final Map<String, String> DEFINITIONS = Map.ofEntries(
            Map.entry("facultiesAndColleges", "Faculties on the reference list plus the Colleges that group them"),
            Map.entry("faculties", "Faculties on the reference list"),
            Map.entry("colleges", "Colleges on the reference list"),
            Map.entry("academicDepartments", "Departments on the reference list"),
            Map.entry("coursesOfStudy", "Programmes offered (not archived), undergraduate and postgraduate"),
            Map.entry("undergraduateProgrammes", "Undergraduate programmes offered"),
            Map.entry("postgraduateProgrammes", "Postgraduate programmes offered"),
            Map.entry("degreeProgrammeTypes", "Distinct awards offered: the undergraduate degree and each postgraduate award (PGD, MA, MSc, MBA, PhD, …)"),
            Map.entry("enrolledStudents", "Students on the register in good standing: active, on probation or deferred"),
            Map.entry("undergraduates", "Enrolled students on undergraduate programmes"),
            Map.entry("postgraduates", "Enrolled students on postgraduate programmes"),
            Map.entry("academicStaff", "Staff in active academic employment on the nominal roll"),
            Map.entry("supportStaff", "Staff in active non-academic employment on the nominal roll"),
            Map.entry("academicAndSupportStaff", "All staff in active employment on the nominal roll"));

    @GetMapping("/statistics")
    @Transactional(readOnly = true)
    public ResponseEntity<Map<String, Object>> statistics() {
        Map<String, Object> row = jdbc.sql("""
                WITH enrolled AS (
                    SELECT s.id, p.category
                      FROM people.student s JOIN ref.programme p ON p.code = s.programme_code
                     WHERE s.status IN ('ACTIVE', 'PROBATION', 'DEFERRED')),
                staff AS (
                    SELECT category, count(*) AS n FROM hrm.employment
                     WHERE status = 'ACTIVE' AND ended_on IS NULL GROUP BY category)
                SELECT (SELECT count(*) FROM ref.faculty)                                                  AS faculties,
                       (SELECT count(*) FROM ref.college)                                                  AS colleges,
                       (SELECT count(*) FROM ref.department)                                               AS departments,
                       (SELECT count(*) FROM ref.programme WHERE NOT archived)                             AS programmes,
                       (SELECT count(*) FROM ref.programme WHERE NOT archived AND category = 'UNDER GRADUATE') AS ug_programmes,
                       (SELECT count(*) FROM ref.programme WHERE NOT archived AND category = 'POST GRADUATE')  AS pg_programmes,
                       (SELECT count(DISTINCT coalesce(nullif(btrim(pg_award), ''), category))
                          FROM ref.programme WHERE NOT archived)                                           AS award_types,
                       (SELECT count(*) FROM enrolled)                                                     AS enrolled,
                       (SELECT count(*) FROM enrolled WHERE category = 'UNDER GRADUATE')                   AS undergraduates,
                       (SELECT count(*) FROM enrolled WHERE category = 'POST GRADUATE')                    AS postgraduates,
                       (SELECT coalesce(sum(n), 0) FROM staff WHERE category = 'ACADEMIC')                 AS academic_staff,
                       (SELECT coalesce(sum(n), 0) FROM staff WHERE category <> 'ACADEMIC')                AS support_staff,
                       (SELECT coalesce(sum(n), 0) FROM staff)                                             AS all_staff,
                       (SELECT count(*) FROM iam.person WHERE staff_number IS NOT NULL AND ended_on IS NULL) AS persons_on_roll,
                       (SELECT name FROM policy.academic_session WHERE state = 'CURRENT' LIMIT 1)          AS current_session,
                       (SELECT name FROM policy.academic_session WHERE state <> 'PLANNED' ORDER BY name DESC LIMIT 1) AS latest_session
                """).query().singleRow();
        List<Map<String, Object>> awards = jdbc.sql("""
                SELECT coalesce(nullif(btrim(pg_award), ''), CASE WHEN category = 'UNDER GRADUATE' THEN 'BACHELOR' ELSE category END) AS award,
                       count(*) AS programmes
                  FROM ref.programme WHERE NOT archived
                 GROUP BY 1 ORDER BY min(CASE WHEN category = 'UNDER GRADUATE' THEN 0 ELSE 1 END), 1
                """).query().listOfRows();

        long academic = n(row, "academic_staff"), support = n(row, "support_staff"), allStaff = n(row, "all_staff");
        // a roll loaded as people without employment records (the nominal-roll upload) still counts as staff
        long staffTotal = Math.max(allStaff, n(row, "persons_on_roll"));

        Map<String, Long> figures = new LinkedHashMap<>();
        figures.put("facultiesAndColleges", n(row, "faculties") + n(row, "colleges"));
        figures.put("faculties", n(row, "faculties"));
        figures.put("colleges", n(row, "colleges"));
        figures.put("academicDepartments", n(row, "departments"));
        figures.put("coursesOfStudy", n(row, "programmes"));
        figures.put("undergraduateProgrammes", n(row, "ug_programmes"));
        figures.put("postgraduateProgrammes", n(row, "pg_programmes"));
        figures.put("degreeProgrammeTypes", n(row, "award_types"));
        figures.put("enrolledStudents", n(row, "enrolled"));
        figures.put("undergraduates", n(row, "undergraduates"));
        figures.put("postgraduates", n(row, "postgraduates"));
        figures.put("academicStaff", academic);
        figures.put("supportStaff", allStaff > 0 ? support : staffTotal - academic);
        figures.put("academicAndSupportStaff", staffTotal);

        NumberFormat fmt = NumberFormat.getIntegerInstance(Locale.UK);
        Map<String, String> display = new LinkedHashMap<>();
        figures.forEach((k, v) -> display.put(k, fmt.format(v)));

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("university", "Rev. Fr. Moses Orshio Adasu University, Makurdi");
        out.put("session", row.get("current_session") != null ? row.get("current_session") : row.get("latest_session"));
        out.put("asAt", OffsetDateTime.now());
        out.put("figures", figures);
        out.put("display", display);
        out.put("awards", awards);
        out.put("definitions", DEFINITIONS);
        return ResponseEntity.ok().cacheControl(CacheControl.maxAge(5, TimeUnit.MINUTES).cachePublic()).body(out);
    }

    private static long n(Map<String, Object> row, String key) {
        Object v = row.get(key);
        return v instanceof Number x ? x.longValue() : 0L;
    }
}
