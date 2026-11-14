package ng.edu.moaum.portal.reports;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V652: the course registration report — one row a student and course registered in a session and semester, read off the
 * registration engine (reporting.course_registration_rows), with the summary by every dimension and the course-by-course figures
 * (registered, sex, card or permit held, attendance). Every office reads within its own bound (OfficeScope): a Head of Department
 * their department, an Examinations Officer their programme, a Faculty Examinations Officer, a Dean or a Faculty Officer their
 * faculty; the GST and EPS offices their own courses; the central offices, ICT and the Database Operator the University. The filters
 * narrow, never widen; every value is checked before it reaches the database and bound, never written into SQL.
 */
@RestController
@RequestMapping("/api/v1/reports/course-registrations")
class CourseRegistrationReportController {

    static final String READERS = "hasAnyAuthority('OFFICE_hod','OFFICE_exams','OFFICE_facultyexams','OFFICE_records','OFFICE_gst','OFFICE_eps',"
            + "'OFFICE_ict','OFFICE_dbops','OFFICE_ictagent','OFFICE_helpdeskhead','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super')";

    /** V752: SIWES — a SIWES registration (the SIWES course registered on the SIWES page), never listed as an ordinary course */
    private static final Set<String> CATEGORIES = Set.of("GST", "EPS", "DEPARTMENTAL", "FACULTY", "OTHER", "CARRY_OVER", "OTHER_COURSES", "SIWES");
    private static final int PAGE_MAX = 500;
    private static final int EXPORT_MAX = 50_000;

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    private final tools.jackson.databind.ObjectMapper json;

    CourseRegistrationReportController(JdbcClient jdbc, OfficeScope scope, tools.jackson.databind.ObjectMapper json) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.json = json;
    }

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    private static String acting() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
    }

    /** the session asked for, or the University's current one */
    private String sessionOf(String session) {
        String s = blank(session);
        if (s != null && !s.matches("^[0-9]{4}/[0-9]{4}$")) {
            throw new DomainRuleViolation("REPORT_SESSION", "A session is written as 2025/2026.");
        }
        return s != null ? s : jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
    }

    /** the filters as the database reads them — each value checked, the faculty, department and programme held to the office's bound */
    Map<String, Object> filters(String fac, String dept, String prog, Integer level, String course, UUID offering, String category,
                                String curriculum, String sex, String reg, String type, String eligible, java.time.LocalDate from, java.time.LocalDate to,
                                String q, Boolean dropped) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        Map<String, Object> f = new LinkedHashMap<>();
        if (b.fac() != null) f.put("fac", b.fac());
        if (b.dept() != null) f.put("dept", b.dept());
        if (b.prog() != null) f.put("prog", b.prog());
        if (level != null) {
            if (level < 100 || level > 900 || level % 100 != 0) throw new DomainRuleViolation("REPORT_LEVEL", "A level is 100 to 900.");
            f.put("level", level);
        }
        String c = blank(course);
        if (c != null) {
            if (!c.matches("^[A-Za-z][A-Za-z0-9 /-]{1,23}$")) throw new DomainRuleViolation("REPORT_COURSE", "A course is named by its code.");
            f.put("course", c.toUpperCase());
        }
        if (offering != null) f.put("offering", offering.toString());
        String cat = blank(category);
        if (cat != null) {
            if (!CATEGORIES.contains(cat.toUpperCase())) throw new DomainRuleViolation("REPORT_CATEGORY", "A category is GST, EPS, departmental, faculty, other, carry-over, the other courses or SIWES.");
            f.put("category", cat.toUpperCase());
        }
        String cur = blank(curriculum);
        if (cur != null) {
            if (!Set.of("BMAS", "CCMAS").contains(cur.toUpperCase())) throw new DomainRuleViolation("REPORT_CURRICULUM", "A curriculum is BMAS or CCMAS.");
            f.put("curriculum", cur.toUpperCase());
        }
        String sx = blank(sex);
        if (sx != null) {
            if (!Set.of("M", "F", "U").contains(sx.toUpperCase())) throw new DomainRuleViolation("REPORT_SEX", "Sex is M, F or U (not stated).");
            f.put("sex", sx.toUpperCase());
        }
        String rs = blank(reg);
        if (rs != null) {
            if (!rs.toUpperCase().matches("^[A-Z_]{3,20}$")) throw new DomainRuleViolation("REPORT_STATUS", "A registration status is named in capitals, e.g. APPROVED.");
            f.put("reg", rs.toUpperCase());
        }
        // V663: the registration type — CURRENT or CARRY_OVER — beside the category, so CARRY-OVER + GST reads
        String ty = blank(type);
        if (ty != null) {
            if (!Set.of("CURRENT", "CARRY_OVER").contains(ty.toUpperCase().replace('-', '_'))) throw new DomainRuleViolation("REPORT_TYPE", "A type is CURRENT or CARRY_OVER.");
            f.put("type", ty.toUpperCase().replace('-', '_'));
        }
        String el = blank(eligible);
        if (el != null) {
            if (!Set.of("YES", "NO").contains(el.toUpperCase())) throw new DomainRuleViolation("REPORT_ELIGIBLE", "Eligible is YES or NO.");
            f.put("eligible", el.toUpperCase());
        }
        if (from != null) f.put("from", from.toString());
        if (to != null) f.put("to", to.toString());
        String qq = blank(q);
        if (qq != null) f.put("q", qq.length() > 80 ? qq.substring(0, 80) : qq);
        if (Boolean.TRUE.equals(dropped)) f.put("dropped", true);
        // the GST and EPS offices read their own courses only
        String office = acting();
        if ("gst".equals(office) || "eps".equals(office)) f.put("office", office.toUpperCase());
        return f;
    }

    private Map<String, Object> scopeOut(Map<String, Object> f) {
        Map<String, Object> s = new LinkedHashMap<>();
        s.put("office", acting());
        s.put("faculty", f.get("fac"));
        s.put("department", f.get("dept"));
        s.put("programme", f.get("prog"));
        s.put("courses", f.get("office"));
        return s;
    }

    /** a page of the rows, each with whether the student's school fees are paid by the card's own test */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> rows(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                             @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                             @RequestParam(required = false) Integer level, @RequestParam(required = false) String course, @RequestParam(required = false) UUID offering,
                             @RequestParam(required = false) String category, @RequestParam(required = false) String curriculum, @RequestParam(required = false) String sex,
                             @RequestParam(required = false) String reg, @RequestParam(required = false) String type, @RequestParam(required = false) String eligible,
                             @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to,
                             @RequestParam(required = false) String q, @RequestParam(required = false) Boolean dropped,
                             @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        String s = sessionOf(session);
        Integer sem = semesterOf(semester);
        Map<String, Object> f = filters(fac, dept, prog, level, course, offering, category, curriculum, sex, reg, type, eligible, from, to, q, dropped);
        int sz = Math.max(1, Math.min(size, PAGE_MAX));
        int pg = Math.max(1, page);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.*, count(*) OVER () AS total
                  FROM reporting.course_registration_rows(:s, :sem, CAST(:f AS jsonb)) r
                 ORDER BY r.faculty, r.department, r.programme, r.level, r.shown_code, r.course_code, r.full_name
                 LIMIT :n OFFSET :off
                """).param("s", s).param("sem", sem, Types.INTEGER).param("f", json.writeValueAsString(f)).param("n", sz).param("off", (long) (pg - 1) * sz)
                .query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total")).longValue();
        // the school fees, by the examination card's own test, for the students on this page only
        List<UUID> ids = rows.stream().map(r -> (UUID) r.get("student_id")).distinct().toList();
        Map<Object, Object> paid = new LinkedHashMap<>();
        if (!ids.isEmpty()) {
            jdbc.sql("SELECT u AS student_id, registration.exam_card_paid(u, :s) AS paid FROM unnest(CAST(:ids AS uuid[])) u")
                    .param("s", s).param("ids", ids.toArray(new UUID[0])).query().listOfRows()
                    .forEach(r -> paid.put(r.get("student_id"), r.get("paid")));
        }
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total");
            m.put("fees_paid", paid.get(r.get("student_id")));
            out.add(m);
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("session", s);
        body.put("semester", sem);
        body.put("page", pg);
        body.put("size", sz);
        body.put("total", total);
        body.put("scope", scopeOut(f));
        body.put("rows", out);
        return body;
    }

    private static Integer semesterOf(Integer semester) {
        if (semester != null && (semester < 1 || semester > 3)) throw new DomainRuleViolation("REPORT_SEMESTER", "A semester is 1, 2 or 3.");
        return semester;
    }

    /** the rows counted once by every dimension: the whole, category, faculty, department, programme, level, sex and course */
    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                @RequestParam(required = false) Integer level, @RequestParam(required = false) String course, @RequestParam(required = false) UUID offering,
                                @RequestParam(required = false) String category, @RequestParam(required = false) String curriculum, @RequestParam(required = false) String sex,
                                @RequestParam(required = false) String reg, @RequestParam(required = false) String type, @RequestParam(required = false) String eligible,
                                @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to,
                                @RequestParam(required = false) String q, @RequestParam(required = false) Boolean dropped) {
        String s = sessionOf(session);
        Integer sem = semesterOf(semester);
        Map<String, Object> f = filters(fac, dept, prog, level, course, offering, category, curriculum, sex, reg, type, eligible, from, to, q, dropped);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("session", s);
        body.put("semester", sem);
        body.put("scope", scopeOut(f));
        body.put("rows", jdbc.sql("SELECT * FROM reporting.course_registration_summary(:s, :sem, CAST(:f AS jsonb)) ORDER BY dimension, registrations DESC, label")
                .param("s", s).param("sem", sem, Types.INTEGER).param("f", json.writeValueAsString(f)).query().listOfRows());
        return body;
    }

    /** each course with its registered students, sex, eligibility, latest attendance sheet and attendance */
    @GetMapping("/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> courses(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                @RequestParam(required = false) Integer level, @RequestParam(required = false) String course,
                                @RequestParam(required = false) String category, @RequestParam(required = false) String curriculum, @RequestParam(required = false) String sex,
                                @RequestParam(required = false) String reg, @RequestParam(required = false) String type, @RequestParam(required = false) String q) {
        String s = sessionOf(session);
        Integer sem = semesterOf(semester);
        Map<String, Object> f = filters(fac, dept, prog, level, course, null, category, curriculum, sex, reg, type, null, null, null, q, null);
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("session", s);
        body.put("semester", sem);
        body.put("scope", scopeOut(f));
        body.put("rows", jdbc.sql("SELECT * FROM reporting.course_registration_courses(:s, :sem, CAST(:f AS jsonb))")
                .param("s", s).param("sem", sem, Types.INTEGER).param("f", json.writeValueAsString(f)).query().listOfRows());
        return body;
    }

    /** every row of the report for an Excel workbook or a PDF, with its reference on the official report register (DBO/REG/…) */
    @GetMapping("/export")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> export(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                               @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                               @RequestParam(required = false) Integer level, @RequestParam(required = false) String course, @RequestParam(required = false) UUID offering,
                               @RequestParam(required = false) String category, @RequestParam(required = false) String curriculum, @RequestParam(required = false) String sex,
                               @RequestParam(required = false) String reg, @RequestParam(required = false) String type, @RequestParam(required = false) String eligible,
                               @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to,
                               @RequestParam(required = false) String q, @RequestParam(required = false) Boolean dropped,
                               @RequestParam(defaultValue = "Course registration report") String title) {
        String s = sessionOf(session);
        Integer sem = semesterOf(semester);
        Map<String, Object> f = filters(fac, dept, prog, level, course, offering, category, curriculum, sex, reg, type, eligible, from, to, q, dropped);
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT r.* FROM reporting.course_registration_rows(:s, :sem, CAST(:f AS jsonb)) r
                 ORDER BY r.faculty, r.department, r.programme, r.level, r.shown_code, r.course_code, r.full_name
                 LIMIT :n
                """).param("s", s).param("sem", sem, Types.INTEGER).param("f", json.writeValueAsString(f)).param("n", EXPORT_MAX + 1).query().listOfRows();
        boolean truncated = rows.size() > EXPORT_MAX;
        if (truncated) rows = rows.subList(0, EXPORT_MAX);
        long students = rows.stream().map(r -> r.get("student_id")).distinct().count();
        Map<String, Object> figures = new LinkedHashMap<>();
        figures.put("registrations", rows.size());
        figures.put("students", students);
        Map<String, Object> filed = new LinkedHashMap<>(f);
        filed.put("session", s);
        if (sem != null) filed.put("semester", sem);
        String t = blank(title) == null ? "Course registration report" : title.trim();
        String reference = jdbc.sql("SELECT reporting.issue_report('REG', :t, CAST(:f AS jsonb), :sc, CAST(:fig AS jsonb), :n, CAST(:p AS jsonb))")
                .param("t", t.length() > 120 ? t.substring(0, 120) : t).param("f", json.writeValueAsString(filed))
                .param("sc", json.writeValueAsString(scopeOut(f))).param("fig", json.writeValueAsString(figures)).param("n", rows.size())
                .param("p", "[\"rows\"]").query(String.class).single();
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("reference", reference);
        body.put("session", s);
        body.put("semester", sem);
        body.put("scope", scopeOut(f));
        body.put("filters", filed);
        body.put("truncated", truncated);
        body.put("rows", rows);
        return body;
    }
}
