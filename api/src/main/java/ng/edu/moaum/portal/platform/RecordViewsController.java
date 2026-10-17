package ng.edu.moaum.portal.platform;

import java.sql.Types;
import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;

import org.springframework.format.annotation.DateTimeFormat;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.validation.annotation.Validated;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V530: who opened a student's record. The student reads which office opened their record and when (the officer's name is Internal
 * Audit's to read); Internal Audit, the Deputy Director of Audit and super read every view, with the person, by student, office,
 * person and day.
 */
@RestController
@Validated
class RecordViewsController {

    static final String READERS = "hasAnyAuthority('OFFICE_audit','OFFICE_deputyaudit','OFFICE_super')";

    private final JdbcClient jdbc;

    RecordViewsController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the student's own record: which office opened it, and when — the last twelve months */
    @GetMapping("/api/v1/me/record-views")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    List<Map<String, Object>> mine(Authentication auth) {
        return jdbc.sql("""
                SELECT v.at, v.office, coalesce(o.label, v.office) AS office_label, v.record
                  FROM people.record_view v LEFT JOIN ref.office o ON o.code = v.office
                 WHERE v.student_id = :me AND v.at > now() - interval '12 months'
                 ORDER BY v.at DESC LIMIT 500
                """).param("me", UUID.fromString(auth.getName())).query().listOfRows();
    }

    /** every view, newest first: a range of days (Lagos), an office, and words found in the student's or the person's name or number */
    @GetMapping("/api/v1/audit/record-views")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> all(@RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate from,
                            @RequestParam(required = false) @DateTimeFormat(iso = DateTimeFormat.ISO.DATE) LocalDate to,
                            @RequestParam(required = false) String office, @RequestParam(required = false) String q,
                            @RequestParam(required = false) UUID student,
                            @RequestParam(defaultValue = "1") @Min(1) int page, @RequestParam(defaultValue = "50") @Min(1) @Max(500) int size) {
        String where = """
                  FROM people.record_view v
                  JOIN people.student s ON s.id = v.student_id
                  LEFT JOIN iam.person p ON p.id = v.viewer_id
                 WHERE (CAST(:from AS date) IS NULL OR v.at >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos'))
                   AND (CAST(:to AS date) IS NULL OR v.at < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos'))
                   AND (CAST(:office AS text) IS NULL OR v.office = CAST(:office AS text))
                   AND (CAST(:student AS uuid) IS NULL OR v.student_id = CAST(:student AS uuid))
                   AND (CAST(:q AS text) IS NULL
                        OR s.surname || ', ' || s.other_names ILIKE '%' || CAST(:q AS text) || '%'
                        OR coalesce(s.matric_no, s.admission_no, '') ILIKE '%' || CAST(:q AS text) || '%'
                        OR coalesce(p.surname || ', ' || p.given_names, '') ILIKE '%' || CAST(:q AS text) || '%'
                        OR coalesce(p.staff_number, '') ILIKE '%' || CAST(:q AS text) || '%')
                """;
        String o = blank(office);
        String w = blank(q);
        long total = jdbc.sql("SELECT count(*)" + where)
                .param("from", from, Types.DATE).param("to", to, Types.DATE).param("office", o, Types.VARCHAR)
                .param("student", student, Types.OTHER).param("q", w, Types.VARCHAR).query(Long.class).single();
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT v.id, v.at, v.record, v.office, coalesce(ro.label, v.office) AS office_label,
                       v.viewer_id, p.surname || ', ' || p.given_names AS viewer, p.staff_number,
                       v.student_id, s.surname || ', ' || s.other_names AS student, coalesce(s.matric_no, s.admission_no) AS number
                """ + where.replace("LEFT JOIN iam.person p ON p.id = v.viewer_id",
                        "LEFT JOIN iam.person p ON p.id = v.viewer_id\n  LEFT JOIN ref.office ro ON ro.code = v.office") + """
                 ORDER BY v.at DESC, v.id
                 LIMIT :size OFFSET :offset
                """)
                .param("from", from, Types.DATE).param("to", to, Types.DATE).param("office", o, Types.VARCHAR)
                .param("student", student, Types.OTHER).param("q", w, Types.VARCHAR)
                .param("size", size).param("offset", (long) (page - 1) * size).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("rows", rows);
        out.put("total", total);
        out.put("page", page);
        out.put("size", size);
        out.put("offices", jdbc.sql("""
                SELECT v.office AS code, coalesce(o.label, v.office) AS label, count(*) AS views
                  FROM people.record_view v LEFT JOIN ref.office o ON o.code = v.office
                 GROUP BY v.office, o.label ORDER BY 2
                """).query().listOfRows());
        return out;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }
}
