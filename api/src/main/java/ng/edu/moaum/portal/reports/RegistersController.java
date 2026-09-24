package ng.edu.moaum.portal.reports;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The two registers management reads whole: every student and every member of staff, filtered by
 * the parameters the returns desk offers (faculty, department, programme, level, sex, status, entry
 * mode and session for a student; faculty, department, rank, category and status for staff) and
 * searched by name or number. Read-only; the rows are the register's own, paged, with the option
 * lists the filter controls are drawn from and a count of everything that matched so a return can
 * say how many it covers.
 */
@RestController
@RequestMapping("/api/v1/reports/registers")
class RegistersController {

    /** who reads the whole register: management, the Registry, Academic Affairs, ICT, the Bursary and Audit */
    private static final String READERS =
            "hasAnyAuthority('OFFICE_vc','OFFICE_dvc','OFFICE_registrar','OFFICE_dregistrar','OFFICE_academic','OFFICE_records',"
            + "'OFFICE_bursar','OFFICE_audit','OFFICE_deputyaudit','OFFICE_hrm','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')";

    private static final int PAGE_MAX = 500;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    RegistersController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the option lists narrowed to the acting office's faculty or department, so a Dean is not offered another faculty */
    @SuppressWarnings("unchecked")
    private static void narrow(Map<String, Object> options, OfficeScope.ReportScope sc) {
        if (sc == null) return;
        for (String key : List.of("faculties", "departments", "programmes")) {
            Object v = options.get(key);
            if (!(v instanceof List<?> list)) continue;
            options.put(key, ((List<Map<String, Object>>) list).stream().filter(o ->
                    key.equals("faculties") ? sc.facultyCode().equals(o.get("code"))
                  : sc.departmentCode() != null ? sc.departmentCode().equals(o.get(key.equals("departments") ? "code" : "department_code"))
                  : sc.facultyCode().equals(o.get("faculty_code"))).toList());
        }
    }

    private static Map<String, Object> scopeOut(OfficeScope.ReportScope sc) {
        return sc == null ? null : Map.of("label", sc.label(), "faculty", sc.facultyName(), "department", sc.departmentName() == null ? "" : sc.departmentName());
    }

    private static String clean(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /** the student register, filtered and searched */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String faculty,
                                 @RequestParam(required = false) String department,
                                 @RequestParam(required = false) String programme,
                                 @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String sex,
                                 @RequestParam(required = false) String status,
                                 @RequestParam(required = false) String entryMode,
                                 @RequestParam(required = false) String session,
                                 @RequestParam(required = false) String q,
                                 @RequestParam(defaultValue = "1") int page,
                                 @RequestParam(defaultValue = "100") int size,
                                 @RequestParam(defaultValue = "true") boolean options) {
        int lim = Math.max(1, Math.min(PAGE_MAX, size));
        int off = Math.max(0, page - 1) * lim;
        StringBuilder where = new StringBuilder(" WHERE true");
        Map<String, Object> params = new LinkedHashMap<>();
        String f = clean(faculty), d = clean(department), p = clean(programme), sx = clean(sex), st = clean(status),
               em = clean(entryMode), ss = clean(session), qq = clean(q);
        OfficeScope.ReportScope sc = scope.reportScope();
        if (sc != null) { f = sc.facultyCode(); if (sc.departmentCode() != null) d = sc.departmentCode(); }
        if (f != null)  { where.append(" AND p.faculty_code = :faculty"); params.put("faculty", f); }
        if (d != null)  { where.append(" AND p.dept_code = :department"); params.put("department", d); }
        if (p != null)  { where.append(" AND s.programme_code = :programme"); params.put("programme", p); }
        if (level != null) { where.append(" AND s.current_level = :level"); params.put("level", level); }
        if (sx != null) { where.append(" AND s.sex = :sex"); params.put("sex", sx.toUpperCase()); }
        if (st != null) { where.append(" AND s.status = :status"); params.put("status", st.toUpperCase()); }
        if (em != null) { where.append(" AND s.entry_mode = :entryMode"); params.put("entryMode", em.toUpperCase()); }
        if (ss != null) { where.append(" AND s.entry_session = :session"); params.put("session", ss); }
        if (qq != null) {
            where.append(" AND (s.surname ILIKE :q OR s.other_names ILIKE :q OR (s.surname || ' ' || s.other_names) ILIKE :q"
                    + " OR s.matric_no ILIKE :q OR s.admission_no ILIKE :q OR s.jamb_reg_no ILIKE :q)");
            params.put("q", "%" + qq + "%");
        }
        String from = " FROM people.student s JOIN ref.programme p ON p.code = s.programme_code"
                + " JOIN ref.faculty f ON f.code = p.faculty_code LEFT JOIN ref.department dp ON dp.code = p.dept_code";

        var count = jdbc.sql("""
                SELECT count(*) AS total, count(*) FILTER (WHERE s.sex = 'F') AS female, count(*) FILTER (WHERE s.sex = 'M') AS male,
                       count(*) FILTER (WHERE s.status IN ('ACTIVE','PROBATION')) AS active,
                       count(*) FILTER (WHERE s.entry_mode = 'POSTGRADUATE') AS postgraduate
                """ + from + where);
        params.forEach(count::param);
        Map<String, Object> summary = count.query().singleRow();
        long total = ((Number) summary.get("total")).longValue();

        var list = jdbc.sql("""
                SELECT s.id, s.matric_no, s.admission_no, s.surname, s.other_names, s.sex, s.status,
                       s.entry_mode, s.entry_session, s.current_level AS level,
                       s.programme_code, p.name AS programme, dp.name AS department, f.name AS faculty
                """ + from + where + " ORDER BY f.name, p.name, s.current_level, s.surname, s.other_names LIMIT :lim OFFSET :off");
        params.forEach(list::param);
        List<Map<String, Object>> rows = list.param("lim", lim).param("off", off).query().listOfRows();

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", Math.max(1, page));
        out.put("size", lim);
        out.put("rows", rows);
        out.put("summary", summary);
        if (options) {   // the desk needs the lists; an export or a printable view fetching pages does not
            Map<String, Object> opts = studentOptions();
            narrow(opts, sc);
            out.put("options", opts);
        }
        out.put("scope", scopeOut(sc));
        return out;
    }

    /** the option lists the student filters are drawn from — what the register actually holds */
    private Map<String, Object> studentOptions() {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        o.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        o.put("programmes", jdbc.sql("""
                SELECT code, name, dept_code AS department_code, faculty_code FROM ref.programme
                 WHERE NOT archived AND EXISTS (SELECT 1 FROM people.student s WHERE s.programme_code = programme.code)
                 ORDER BY name""").query().listOfRows());
        o.put("sessions", jdbc.sql("SELECT DISTINCT entry_session AS name FROM people.student ORDER BY entry_session DESC").query().listOfRows());
        o.put("levels", List.of(100, 200, 300, 400, 500, 600, 700, 800, 900));
        o.put("statuses", List.of("ADMITTED", "ACTIVE", "PROBATION", "DEFERRED", "SUSPENDED", "RUSTICATED", "WITHDRAWN",
                "EXPELLED", "TRANSFERRED_OUT", "GRADUATED", "DECEASED", "DORMANT", "VOLUNTARY_WITHDRAWAL"));
        o.put("entryModes", List.of("UTME", "DIRECT_ENTRY", "TRANSFER", "POSTGRADUATE", "JUPEB", "SANDWICH"));
        return o;
    }

    /** the staff register, filtered and searched: every person with a staff number, with what HR holds on them */
    @GetMapping("/staff")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> staff(@RequestParam(required = false) String faculty,
                              @RequestParam(required = false) String department,
                              @RequestParam(required = false) String rank,
                              @RequestParam(required = false) String category,
                              @RequestParam(required = false) String status,
                              @RequestParam(required = false) String office,
                              @RequestParam(required = false) String q,
                              @RequestParam(defaultValue = "1") int page,
                              @RequestParam(defaultValue = "100") int size,
                              @RequestParam(defaultValue = "true") boolean options) {
        int lim = Math.max(1, Math.min(PAGE_MAX, size));
        int off = Math.max(0, page - 1) * lim;
        StringBuilder where = new StringBuilder(" WHERE pe.staff_number IS NOT NULL");
        Map<String, Object> params = new LinkedHashMap<>();
        String f = clean(faculty), d = clean(department), r = clean(rank), c = clean(category), st = clean(status),
               of = clean(office), qq = clean(q);
        OfficeScope.ReportScope sc = scope.reportScope();
        if (sc != null) { f = sc.facultyCode(); if (sc.departmentCode() != null) d = sc.departmentCode(); }
        if (f != null)  { where.append(" AND dp.faculty_code = :faculty"); params.put("faculty", f); }
        if (d != null)  { where.append(" AND sr.home_department = :department"); params.put("department", d); }
        if (r != null)  { where.append(" AND upper(sr.present_rank) = :rank"); params.put("rank", r.toUpperCase()); }
        if (c != null)  {
            // category comes from the employment record when there is one, else from the offices held
            where.append(" AND coalesce(e.category, CASE WHEN ax.academic THEN 'ACADEMIC' ELSE 'NON_ACADEMIC' END) = :category");
            params.put("category", c.toUpperCase());
        }
        if (st != null) {
            if ("ENDED".equalsIgnoreCase(st)) where.append(" AND (pe.ended_on IS NOT NULL OR e.status = 'ENDED')");
            else { where.append(" AND pe.ended_on IS NULL AND coalesce(e.status, 'ACTIVE') = :status"); params.put("status", st.toUpperCase()); }
        }
        if (of != null) {
            where.append(" AND EXISTS (SELECT 1 FROM iam.office_assignment a WHERE a.person_id = pe.id AND a.office_code = :office"
                    + " AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date))");
            params.put("office", of);
        }
        if (qq != null) {
            where.append(" AND (pe.surname ILIKE :q OR pe.given_names ILIKE :q OR (pe.surname || ' ' || pe.given_names) ILIKE :q"
                    + " OR pe.staff_number ILIKE :q OR pe.email ILIKE :q)");
            params.put("q", "%" + qq + "%");
        }
        String from = """
                 FROM iam.person pe
                 LEFT JOIN hrm.staff_record sr ON sr.person_id = pe.id
                 LEFT JOIN hrm.employment e ON e.person_id = pe.id AND e.status <> 'ENDED'
                 LEFT JOIN ref.department dp ON dp.code = sr.home_department
                 LEFT JOIN ref.faculty f ON f.code = dp.faculty_code
                 LEFT JOIN LATERAL (
                    SELECT string_agg(a.office_code, ', ' ORDER BY a.office_code) AS offices,
                           bool_or(a.office_code IN ('lecturer','hod','dean','pgschool','provost')) AS academic
                      FROM iam.office_assignment a
                     WHERE a.person_id = pe.id AND a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 ) ax ON true
                """;

        var count = jdbc.sql("""
                SELECT count(*) AS total,
                       count(*) FILTER (WHERE coalesce(e.category, CASE WHEN ax.academic THEN 'ACADEMIC' ELSE 'NON_ACADEMIC' END) = 'ACADEMIC') AS academic,
                       count(*) FILTER (WHERE sr.sex = 'F') AS female, count(*) FILTER (WHERE sr.sex = 'M') AS male,
                       count(*) FILTER (WHERE pe.ended_on IS NULL AND coalesce(e.status, 'ACTIVE') = 'ACTIVE') AS active
                """ + from + where);
        params.forEach(count::param);
        Map<String, Object> summary = count.query().singleRow();
        long total = ((Number) summary.get("total")).longValue();

        var list = jdbc.sql("""
                SELECT pe.id, pe.staff_number, pe.surname, pe.given_names, pe.email, pe.phone,
                       sr.sex, sr.present_rank AS rank, sr.conuass_step, sr.date_first_appointment,
                       sr.home_department AS department_code, dp.name AS department, f.name AS faculty,
                       coalesce(e.category, CASE WHEN ax.academic THEN 'ACADEMIC' ELSE 'NON_ACADEMIC' END) AS category,
                       e.grade, e.step, e.appointment_date,
                       CASE WHEN pe.ended_on IS NOT NULL THEN 'ENDED' ELSE coalesce(e.status, 'ACTIVE') END AS status,
                       ax.offices
                """ + from + where + " ORDER BY f.name NULLS LAST, dp.name NULLS LAST, pe.surname, pe.given_names LIMIT :lim OFFSET :off");
        params.forEach(list::param);
        List<Map<String, Object>> rows = list.param("lim", lim).param("off", off).query().listOfRows();

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", total);
        out.put("page", Math.max(1, page));
        out.put("size", lim);
        out.put("rows", rows);
        out.put("summary", summary);
        if (options) {
            Map<String, Object> opts = staffOptions();
            narrow(opts, sc);
            out.put("options", opts);
        }
        out.put("scope", scopeOut(sc));
        return out;
    }

    private Map<String, Object> staffOptions() {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("faculties", jdbc.sql("SELECT code, name FROM ref.faculty ORDER BY name").query().listOfRows());
        o.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department WHERE ended_on IS NULL ORDER BY name").query().listOfRows());
        List<String> ranks = new ArrayList<>(jdbc.sql("""
                SELECT DISTINCT upper(present_rank) AS r FROM hrm.staff_record WHERE present_rank IS NOT NULL ORDER BY r
                """).query(String.class).list());
        o.put("ranks", ranks);
        o.put("categories", List.of("ACADEMIC", "NON_ACADEMIC"));
        o.put("statuses", List.of("ACTIVE", "SUSPENDED", "ENDED"));
        o.put("offices", jdbc.sql("SELECT code, label AS name FROM ref.office ORDER BY label").query().listOfRows());
        return o;
    }
}
