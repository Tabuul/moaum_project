package ng.edu.moaum.portal.credentials;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ng.edu.moaum.portal.shared.DomainRuleViolation;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V749: who has and who has not brought their identity information up to date — the University's briefs of 12 November 2026, for
 * the administrators. Students in study (credentials.identity_completion_students / _student_list): the blood group confirmed, a
 * photograph on file, the matriculation number — what the identity card asks — by faculty, department, programme and level. Staff
 * in the University's service (credentials.identity_completion_staff / _staff_list, V698's roster): the photograph enhanced and
 * accepted, the e-mail verified, the blood group confirmed, by faculty, unit and category, and who cannot sign in to be asked.
 * Each list is filtered by what is missing, searched, and read a page at a time (export: up to 20,000 rows).
 *
 * <p>Students: the Directorate of ICT, the administrators, the Registry (Registrar, Deputy Registrar, Records), Student Affairs and
 * the Security Unit's card desk. Staff: the Directorate of ICT, the administrators, Human Resources, the Registrar and Deputy
 * Registrar, and the Security Unit. The faculty and department offices are not readers: the lists cover the whole University.
 */
@RestController
@RequestMapping("/api/v1/identity/completion")
class IdentityCompletionController {

    static final String STUDENT_READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_dsa','OFFICE_security')";
    static final String STAFF_READERS = "hasAnyAuthority('OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_hrm','OFFICE_registrar',"
            + "'OFFICE_dregistrar','OFFICE_security')";
    static final Set<String> STUDENT_MISSING = Set.of("BLOOD", "PHOTO", "MATRIC", "ANY");
    static final Set<String> STAFF_MISSING = Set.of("PHOTO", "EMAIL", "BLOOD", "ANY");
    static final List<String> CATEGORIES = List.of("ACADEMIC", "NON_ACADEMIC");
    static final int EXPORT_ROWS = 20000;

    private final JdbcClient jdbc;

    IdentityCompletionController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the counts for the students in study the filters name, with the faculties, departments and programmes to filter by */
    @GetMapping("/students")
    @PreAuthorize(STUDENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                                 @RequestParam(required = false) String programme, @RequestParam(required = false) Integer level) {
        Map<String, Object> counts = jdbc.sql("SELECT * FROM credentials.identity_completion_students(:f, :d, :p, :l)")
                .param("f", blank(faculty), Types.VARCHAR).param("d", blank(department), Types.VARCHAR)
                .param("p", blank(programme), Types.VARCHAR).param("l", level, Types.INTEGER).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", counts);
        out.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department ORDER BY name").query().listOfRows());
        out.put("programmes", jdbc.sql("""
                SELECT code, name, dept_code, faculty_code FROM ref.programme WHERE NOT coalesce(archived, false) ORDER BY name
                """).query().listOfRows());
        return out;
    }

    /** the students behind the counts: filtered as they are, by what is missing (BLOOD, PHOTO, MATRIC, ANY), searched by name or number */
    @GetMapping("/students/list")
    @PreAuthorize(STUDENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> studentList(@RequestParam(required = false) String faculty, @RequestParam(required = false) String department,
                                    @RequestParam(required = false) String programme, @RequestParam(required = false) Integer level,
                                    @RequestParam(required = false) String missing, @RequestParam(required = false) String q,
                                    @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size,
                                    @RequestParam(defaultValue = "false") boolean export) {
        String m = missing(missing, STUDENT_MISSING, "BLOOD (blood group not confirmed), PHOTO, MATRIC (no matriculation number) or ANY");
        int sz = export ? EXPORT_ROWS : Math.max(1, Math.min(size, 200));
        int pg = export ? 0 : Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM credentials.identity_completion_student_list(:f, :d, :p, :l, :m, :q, :size, :off)")
                .param("f", blank(faculty), Types.VARCHAR).param("d", blank(department), Types.VARCHAR)
                .param("p", blank(programme), Types.VARCHAR).param("l", level, Types.INTEGER).param("m", m, Types.VARCHAR)
                .param("q", blank(q), Types.VARCHAR).param("size", sz).param("off", pg * sz).query().listOfRows();
        return page(rows, pg, sz);
    }

    /** the counts for the staff in service the filters name, with the faculties and units to filter by */
    @GetMapping("/staff")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> staff(@RequestParam(required = false) String faculty, @RequestParam(required = false) String unit,
                              @RequestParam(required = false) String category) {
        Map<String, Object> counts = jdbc.sql("SELECT * FROM credentials.identity_completion_staff(:f, :u, :c)")
                .param("f", blank(faculty), Types.VARCHAR).param("u", blank(unit), Types.VARCHAR).param("c", category(category), Types.VARCHAR)
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("counts", counts);
        // what the counts can be narrowed by: every faculty and unit a member of staff in service is in
        out.put("faculties", jdbc.sql("""
                SELECT DISTINCT r.faculty_code AS code, r.faculty AS name FROM credentials.identity_staff_rows(NULL, NULL, NULL) r
                 WHERE r.faculty_code IS NOT NULL AND r.faculty IS NOT NULL ORDER BY r.faculty
                """).query().listOfRows());
        out.put("units", jdbc.sql("""
                SELECT DISTINCT r.unit_code AS code, r.unit AS name, r.faculty_code FROM credentials.identity_staff_rows(NULL, NULL, NULL) r
                 WHERE r.unit_code IS NOT NULL AND r.unit IS NOT NULL ORDER BY r.unit
                """).query().listOfRows());
        out.put("categories", CATEGORIES);
        return out;
    }

    /** the staff behind the counts: filtered as they are, by what is missing (PHOTO, EMAIL, BLOOD, ANY), searched by staff number,
     *  name or e-mail */
    @GetMapping("/staff/list")
    @PreAuthorize(STAFF_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> staffList(@RequestParam(required = false) String faculty, @RequestParam(required = false) String unit,
                                  @RequestParam(required = false) String category, @RequestParam(required = false) String missing,
                                  @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                                  @RequestParam(defaultValue = "50") int size, @RequestParam(defaultValue = "false") boolean export) {
        String m = missing(missing, STAFF_MISSING, "PHOTO (not enhanced and accepted), EMAIL (not verified), BLOOD (not confirmed) or ANY");
        int sz = export ? EXPORT_ROWS : Math.max(1, Math.min(size, 200));
        int pg = export ? 0 : Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM credentials.identity_completion_staff_list(:f, :u, :c, :m, :q, :size, :off)")
                .param("f", blank(faculty), Types.VARCHAR).param("u", blank(unit), Types.VARCHAR).param("c", category(category), Types.VARCHAR)
                .param("m", m, Types.VARCHAR).param("q", blank(q), Types.VARCHAR).param("size", sz).param("off", pg * sz).query().listOfRows();
        return page(rows, pg, sz);
    }

    private static Map<String, Object> page(List<Map<String, Object>> rows, int page, int size) {
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        List<Map<String, Object>> out = rows.stream().map(r -> {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total");
            return m;
        }).toList();
        return Map.of("rows", out, "total", total, "page", page, "size", size);
    }

    private static String missing(String v, Set<String> allowed, String words) {
        String m = blank(v) == null ? null : v.trim().toUpperCase();
        if (m != null && !allowed.contains(m)) {
            throw new DomainRuleViolation("IDENTITY_FILTER", "What is missing is " + words + ".",
                    new DomainRuleViolation.Remedy("Choose the filter from the list on the page.", "You"));
        }
        return m;
    }

    private static String category(String v) {
        String c = blank(v) == null ? null : v.trim().toUpperCase().replace(' ', '_').replace('-', '_');
        if (c != null && !CATEGORIES.contains(c)) {
            throw new DomainRuleViolation("IDENTITY_FILTER", "A category is ACADEMIC or NON_ACADEMIC.",
                    new DomainRuleViolation.Remedy("Choose the category from the list on the page.", "You"));
        }
        return c;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }
}
