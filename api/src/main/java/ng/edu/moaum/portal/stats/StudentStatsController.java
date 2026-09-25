package ng.edu.moaum.portal.stats;

import java.sql.Types;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Student statistics (V257): one engine every dashboard reads. The population is every student in study; each
 * has a fee position and a registration for the session or semester asked for, from reporting.student_positions.
 * The summary counts them — in all, paid, registered, paid but not registered, not paid, no charge stated — and
 * the same by faculty, department, programme and (for postgraduates) degree type; the list pages the very rows
 * a figure counted. The scope is the acting office's, held on the server: the Postgraduate School sees only
 * postgraduates, the College of Health Sciences only its own students, a Dean their faculty, a Head their
 * department; the University's offices see everyone. Amounts are shown to the offices that hold the purse.
 */
@RestController
@RequestMapping("/api/v1/stats/students")
class StudentStatsController {

    private static final String READERS = "hasAnyAuthority('OFFICE_registrar','OFFICE_dregistrar','OFFICE_bursar','OFFICE_academic','OFFICE_records',"
            + "'OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_dvc','OFFICE_vc','OFFICE_pgschool','OFFICE_pgsecretary',"
            + "'OFFICE_provost','OFFICE_collegesecretary','OFFICE_financecontroller','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_exams')";
    private static final Set<String> PG_OFFICES = Set.of("pgschool", "pgsecretary");
    private static final Set<String> CHS_OFFICES = Set.of("provost", "collegesecretary", "financecontroller");
    private static final Set<String> MONEY = Set.of("bursar", "financecontroller", "registrar", "dregistrar", "super", "admin",
            "pgschool", "pgsecretary", "provost", "collegesecretary", "dvc", "vc");
    private static final Set<String> STATUSES = Set.of("ACTIVE", "PROBATION", "ADMITTED");
    private static final Set<String> WHICH = Set.of("ALL", "PAID", "REGISTERED", "PAID_NOT_REGISTERED", "NOT_PAID", "NO_CHARGE", "NOT_REGISTERED");

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    StudentStatsController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the scope the acting office is held to, and the predicates that hold it */
    record Bound(String kind, String label, String faculty, String dept, boolean money) {
    }

    private Bound bound() {
        String office = AuditContextHolder.current().map(c -> c.actorOffice()).orElse("");
        boolean money = MONEY.contains(office);
        if (PG_OFFICES.contains(office)) return new Bound("PG_SCHOOL", "Postgraduate School", null, null, money);
        if (CHS_OFFICES.contains(office)) return new Bound("COLLEGE", "College of Health Sciences", null, null, money);
        if (scope.actingFacultyOffice()) {
            String f = scope.actingFaculty();
            return new Bound("FACULTY", "Faculty", f == null ? "__none__" : f, null, money);
        }
        if (scope.actingDepartmentOffice()) {
            String d = scope.actingDept();
            return new Bound("DEPARTMENT", "Department", null, d == null ? "__none__" : d, money);
        }
        return new Bound("UNIVERSITY", "University", null, null, money);
    }

    /** the filters, each applied only within the bound: a faculty outside a Dean's own is simply empty */
    record Filters(String session, Integer semester, String fac, String dept, String prog, Integer level, String status, String degree, String q) {
    }

    private Filters filters(String session, Integer semester, String fac, String dept, String prog, Integer level, String status, String degree, String q) {
        String s = session != null && session.matches("\\d{4}/\\d{4}") ? session : currentSession();
        Integer sem = semester == null ? null : semester >= 1 && semester <= 3 ? semester : null;
        return new Filters(s, sem, blank(fac), blank(dept), blank(prog), level, status == null ? null : STATUSES.contains(status.toUpperCase()) ? status.toUpperCase() : null, blank(degree),
                q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%");
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private String currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional()
                .orElseGet(() -> jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC LIMIT 1").query(String.class).single());
    }

    private static final String ROWS = """
            SELECT * FROM reporting.student_positions(:s, :sem) r
             WHERE (:pg::boolean IS NULL OR r.is_pg = :pg)
               AND (:chs::boolean IS NULL OR r.is_chs = :chs)
               AND (:bf::text IS NULL OR r.faculty_code = :bf)
               AND (:bd::text IS NULL OR r.dept_code = :bd)
               AND (:fac::text IS NULL OR r.faculty_code = :fac)
               AND (:dept::text IS NULL OR r.dept_code = :dept)
               AND (:prog::text IS NULL OR r.programme_code = :prog)
               AND (:level::int IS NULL OR r.level = :level)
               AND (:status::text IS NULL OR r.status = :status)
               AND (:degree::text IS NULL OR r.degree_type = :degree)
               AND (:q::text IS NULL OR lower(r.surname || ' ' || r.other_names) LIKE :q OR lower(coalesce(r.number, '')) LIKE :q
                    OR lower(coalesce(r.last_reference, '')) LIKE :q OR lower(r.programme) LIKE :q OR lower(r.department) LIKE :q OR lower(r.faculty) LIKE :q)
            """;

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec q, Bound b, Filters f) {
        return q.param("s", f.session()).param("sem", f.semester(), Types.INTEGER)
                .param("pg", "PG_SCHOOL".equals(b.kind()) ? Boolean.TRUE : null, Types.BOOLEAN)
                .param("chs", "COLLEGE".equals(b.kind()) ? Boolean.TRUE : null, Types.BOOLEAN)
                .param("bf", b.faculty(), Types.VARCHAR).param("bd", b.dept(), Types.VARCHAR)
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("level", f.level(), Types.INTEGER).param("status", f.status(), Types.VARCHAR).param("degree", f.degree(), Types.VARCHAR)
                .param("q", f.q(), Types.VARCHAR);
    }

    /** the figures: in all, and by faculty, department, programme and degree type — one pass over the rows */
    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String status, @RequestParam(required = false) String degree,
                                @RequestParam(required = false) String q) {
        Bound b = bound();
        Filters f = filters(session, semester, fac, dept, prog, level, status, degree, q);
        List<Map<String, Object>> groups = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + """
                )
                SELECT grouping(faculty_code) AS g_f, grouping(dept_code) AS g_d, grouping(programme_code) AS g_p, grouping(degree_type) AS g_t,
                       faculty_code, faculty, dept_code, department, programme_code, programme, degree_type,
                       count(*) AS total,
                       count(*) FILTER (WHERE paid) AS paid,
                       count(*) FILTER (WHERE registered) AS registered,
                       count(*) FILTER (WHERE paid AND NOT registered) AS paid_not_registered,
                       count(*) FILTER (WHERE pay_status IN ('PART_PAYMENT','NOT_PAID')) AS not_paid,
                       count(*) FILTER (WHERE pay_status = 'NO_CHARGE') AS no_charge,
                       count(*) FILTER (WHERE NOT registered) AS not_registered,
                       coalesce(sum(payable), 0) AS payable, coalesce(sum(paid_amount), 0) AS paid_amount, coalesce(sum(outstanding), 0) AS outstanding
                  FROM r
                 GROUP BY GROUPING SETS ((), (faculty_code, faculty), (faculty_code, faculty, dept_code, department),
                                         (faculty_code, faculty, dept_code, department, programme_code, programme), (degree_type))
                 ORDER BY faculty, department, programme, degree_type
                """), b, f).query().listOfRows();
        Map<String, Object> totals = null;
        List<Map<String, Object>> byFaculty = new ArrayList<>(), byDepartment = new ArrayList<>(), byProgramme = new ArrayList<>(), byDegree = new ArrayList<>();
        for (Map<String, Object> g : groups) {
            int gf = ((Number) g.get("g_f")).intValue(), gd = ((Number) g.get("g_d")).intValue(), gp = ((Number) g.get("g_p")).intValue(), gt = ((Number) g.get("g_t")).intValue();
            Map<String, Object> row = counts(g, b.money());
            if (gf == 1 && gd == 1 && gp == 1 && gt == 1) totals = row;
            else if (gt == 0) { if (g.get("degree_type") != null) { row.put("degree_type", g.get("degree_type")); byDegree.add(row); } }
            else if (gp == 0) { row.put("programme_code", g.get("programme_code")); row.put("programme", g.get("programme")); row.put("dept_code", g.get("dept_code")); row.put("department", g.get("department")); row.put("faculty_code", g.get("faculty_code")); row.put("faculty", g.get("faculty")); byProgramme.add(row); }
            else if (gd == 0) { row.put("dept_code", g.get("dept_code")); row.put("department", g.get("department")); row.put("faculty_code", g.get("faculty_code")); row.put("faculty", g.get("faculty")); byDepartment.add(row); }
            else { row.put("faculty_code", g.get("faculty_code")); row.put("faculty", g.get("faculty")); byFaculty.add(row); }
        }
        if (totals == null) totals = counts(Map.of("total", 0L, "paid", 0L, "registered", 0L, "paid_not_registered", 0L, "not_paid", 0L, "no_charge", 0L, "not_registered", 0L,
                "payable", java.math.BigDecimal.ZERO, "paid_amount", java.math.BigDecimal.ZERO, "outstanding", java.math.BigDecimal.ZERO), b.money());

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", Map.of("kind", b.kind(), "label", b.label(), "faculty", String.valueOf(b.faculty()), "department", String.valueOf(b.dept()), "money", b.money()));
        out.put("session", f.session());
        out.put("semester", f.semester());
        out.put("totals", totals);
        out.put("byFaculty", byFaculty);
        out.put("byDepartment", byDepartment);
        out.put("byProgramme", byProgramme);
        out.put("byDegreeType", byDegree);
        out.put("options", options(b, f));
        out.put("window", jdbc.sql("""
                SELECT number, registration_opens, registration_closes, state FROM policy.semester WHERE session = :s ORDER BY number
                """).param("s", f.session()).query().listOfRows());
        return out;
    }

    private static Map<String, Object> counts(Map<String, Object> g, boolean money) {
        Map<String, Object> row = new LinkedHashMap<>();
        for (String k : List.of("total", "paid", "registered", "paid_not_registered", "not_paid", "no_charge", "not_registered")) row.put(k, ((Number) g.get(k)).longValue());
        if (money) for (String k : List.of("payable", "paid_amount", "outstanding")) row.put(k, g.get(k));
        return row;
    }

    /** what the filter bar may offer, within the bound */
    private Map<String, Object> options(Bound b, Filters f) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        o.put("semesters", jdbc.sql("SELECT number FROM policy.semester WHERE session = :s ORDER BY number").param("s", f.session()).query(Integer.class).list());
        String where = switch (b.kind()) {
            case "PG_SCHOOL" -> " AND p.category = 'POST GRADUATE'";
            case "COLLEGE" -> " AND f.college_code = 'CHS'";
            case "FACULTY" -> " AND f.code = :bf";
            case "DEPARTMENT" -> " AND d.code = :bd";
            default -> "";
        };
        String sql = """
                SELECT DISTINCT f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department, p.code AS programme_code, p.name AS programme
                  FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code JOIN ref.department d ON d.code = p.dept_code
                 WHERE NOT p.archived""" + where + " ORDER BY f.name, d.name, p.name";
        JdbcClient.StatementSpec q = jdbc.sql(sql);
        if ("FACULTY".equals(b.kind())) q = q.param("bf", b.faculty());
        if ("DEPARTMENT".equals(b.kind())) q = q.param("bd", b.dept());
        List<Map<String, Object>> tree = q.query().listOfRows();
        o.put("programmes", tree);
        o.put("levels", "PG_SCHOOL".equals(b.kind()) ? List.of(700, 800, 900) : List.of(100, 200, 300, 400, 500, 600, 700, 800, 900));
        o.put("statuses", List.of("ACTIVE", "PROBATION", "ADMITTED"));
        o.put("degreeTypes", "PG_SCHOOL".equals(b.kind()) || "UNIVERSITY".equals(b.kind()) ? List.of("PGD", "MASTERS", "MPHIL", "PHD") : List.of());
        return o;
    }

    /** the students behind a figure: the same rows, the same filters, a page at a time, names A–Z */
    @GetMapping
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                 @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String status, @RequestParam(required = false) String degree,
                                 @RequestParam(defaultValue = "ALL") String which, @RequestParam(required = false) String q,
                                 @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        Bound b = bound();
        Filters f = filters(session, semester, fac, dept, prog, level, status, degree, q);
        String w = WHICH.contains(which.toUpperCase()) ? which.toUpperCase() : "ALL";
        String pred = switch (w) {
            case "PAID" -> " AND r.paid";
            case "REGISTERED" -> " AND r.registered";
            case "PAID_NOT_REGISTERED" -> " AND r.paid AND NOT r.registered";
            case "NOT_PAID" -> " AND r.pay_status IN ('PART_PAYMENT','NOT_PAID')";
            case "NO_CHARGE" -> " AND r.pay_status = 'NO_CHARGE'";
            case "NOT_REGISTERED" -> " AND NOT r.registered";
            default -> "";
        };
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + """
                )
                SELECT count(*) OVER () AS total_rows, r.*
                  FROM r
                 WHERE true""" + pred + """
                 ORDER BY r.surname, r.other_names, r.number
                 LIMIT :n OFFSET :o
                """), b, f).param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> x = new LinkedHashMap<>(r);
            x.remove("total_rows");
            if (!b.money()) { x.remove("payable"); x.remove("paid_amount"); x.remove("outstanding"); x.remove("last_reference"); }
            out.add(x);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scope", Map.of("kind", b.kind(), "label", b.label(), "money", b.money()));
        res.put("session", f.session());
        res.put("semester", f.semester());
        res.put("which", w);
        res.put("total", total);
        res.put("page", pg);
        res.put("size", sz);
        res.put("rows", out);
        return res;
    }
}
