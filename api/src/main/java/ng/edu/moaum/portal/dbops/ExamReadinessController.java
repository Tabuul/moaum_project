package ng.edu.moaum.portal.dbops;

import java.sql.Types;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V640: examination readiness, under /api/v1/reports/exam-readiness — for a session and semester, every student of the scope:
 * paid and registered, paid and not registered, not paid (a fee charged and nothing paid), no fee stated (never counted as not paid).
 * Paid is the examination card's own test (a confirmed school-fees payment for the session) unless the Bursary's rule — paid in
 * full — is asked for; registered is the student statistics engine's own, across the postgraduate, College and University
 * registers. By faculty, department, programme, level, programme type or academic status, for one course, or each course a
 * department offers; every figure lists its students; a package of six reports is issued under one reference. Every read is held
 * to the acting office's scope on the server, read-only, and logged.
 */
@RestController
@RequestMapping("/api/v1/reports/exam-readiness")
class ExamReadinessController {

    private static final Set<String> BY = Set.of("faculty", "department", "programme", "level", "type", "status", "all");
    private static final Set<String> CATEGORIES = Set.of("ALL", "PAID_REGISTERED", "PAID_NOT_REGISTERED", "NOT_PAID", "NOT_PAID_REGISTERED",
            "NO_FEE_STATED", "EXAM_CARD", "EXCEPTIONS", "PART_PAID");
    private static final Map<String, String> SORTS = Map.of(
            "name", "r.surname, r.other_names, r.matric_no",
            "matric", "r.matric_no NULLS LAST, r.surname",
            "programme", "r.programme, r.level, r.surname, r.other_names",
            "level", "r.level, r.surname, r.other_names",
            "outstanding", "r.outstanding DESC, r.surname, r.other_names",
            "department", "r.department, r.programme, r.surname, r.other_names");
    static final List<String> PARTS = List.of("Report 1 — Paid and registered", "Report 2 — Paid but not registered", "Report 3 — Not paid",
            "Report 4 — Course-level registration", "Report 5 — Department summary", "Report 6 — Faculty summary");

    private final JdbcClient jdbc;
    private final Operations ops;

    ExamReadinessController(JdbcClient jdbc, Operations ops) {
        this.jdbc = jdbc;
        this.ops = ops;
    }

    /** the filters of a request, the scope held on the server */
    record Filter(String session, int semester, OfficeScope.Bound bound, Integer level, String type, String course, String rule, String astatus) {
        Map<String, Object> words() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("session", session);
            m.put("semester", semester);
            if (bound.fac() != null) m.put("faculty", bound.fac());
            if (bound.dept() != null) m.put("department", bound.dept());
            if (bound.prog() != null) m.put("programme", bound.prog());
            if (level != null) m.put("level", level);
            if (type != null) m.put("programmeType", type);
            if (course != null) m.put("course", course);
            if (astatus != null) m.put("academicStatus", astatus);
            m.put("paidRule", rule);
            return m;
        }
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private Filter filter(String session, Integer semester, String fac, String dept, String prog, Integer level, String type, String course,
                          String rule, String astatus) {
        Map<String, Object> period = jdbc.sql("SELECT session, semester FROM reporting.readiness_period()").query().singleRow();
        String s = session != null && session.matches("[0-9]{4}/[0-9]{4}") ? session : (String) period.get("session");
        if (s == null) {
            throw new DomainRuleViolation("READINESS_SESSION", "No session is current; choose the session the report is for.",
                    new DomainRuleViolation.Remedy("Pick the session in the bar.", "You"));
        }
        int sem = semester != null && semester >= 1 && semester <= 3 ? semester : ((Number) period.get("semester")).intValue();
        String t = blank(type) == null ? null : type.trim().toUpperCase();
        if (t != null && !t.matches("[A-Z_]{2,30}")) t = null;
        String c = blank(course);
        if (c != null) {
            c = jdbc.sql("SELECT code FROM catalogue.course WHERE upper(code) = upper(:c)").param("c", c).query(String.class).optional()
                    .orElseThrow(() -> new DomainRuleViolation("READINESS_COURSE", "There is no course " + course + ".",
                            new DomainRuleViolation.Remedy("Choose the course from the list.", "You")));
        }
        Integer lv = level != null && level >= 100 && level <= 900 ? level : null;
        String a = blank(astatus) == null ? null : astatus.trim().toUpperCase();
        if (a != null && !a.matches("[A-Z_0-9]{2,30}")) a = null;
        return new Filter(s, sem, ops.bound(fac, dept, prog), lv, t, c, "FULL".equalsIgnoreCase(rule) ? "FULL" : "CARD", a);
    }

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec q, Filter f) {
        return q.param("s", f.session()).param("sem", f.semester())
                .param("f", f.bound().fac(), Types.VARCHAR).param("d", f.bound().dept(), Types.VARCHAR).param("p", f.bound().prog(), Types.VARCHAR)
                .param("l", f.level(), Types.INTEGER).param("t", f.type(), Types.VARCHAR).param("c", f.course(), Types.VARCHAR)
                .param("rule", f.rule()).param("astatus", f.astatus(), Types.VARCHAR);
    }

    /** the planner is told to keep one plan for the session's fee positions: a custom plan for a constant session took many times
     *  longer (the School Fees Report's finding, 19 Oct 2026) */
    private void generic() {
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_generic_plan', true)").query().singleRow();
    }

    private static final String ROWS = """
            FROM reporting.exam_readiness(CAST(:s AS text), CAST(:sem AS int), CAST(:f AS text), CAST(:d AS text), CAST(:p AS text),
                                          CAST(:l AS int), CAST(:t AS text), CAST(:c AS text), CAST(:rule AS text)) r
            """;

    /** the period a report reads when none is chosen, the sessions and the programme types to choose from */
    @GetMapping("/options")
    @PreAuthorize(Operations.READINESS_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> options() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("period", jdbc.sql("SELECT session, semester FROM reporting.readiness_period()").query().singleRow());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session WHERE state IN ('CURRENT', 'CLOSED') ORDER BY starts_on DESC LIMIT 12")
                .query(String.class).list());
        out.put("types", jdbc.sql("SELECT code, label FROM finance.programme_type ORDER BY ord, code").query().listOfRows());
        OfficeScope.Bound b = ops.bound(null, null, null);
        out.put("scope", Map.of("words", ops.words(b), "faculty", b.fac() == null ? "" : b.fac(), "department", b.dept() == null ? "" : b.dept(),
                "programme", b.prog() == null ? "" : b.prog()));
        out.put("amounts", Operations.amounts());
        return out;
    }

    /** the readiness counted by faculty, department, programme, level, programme type or academic status, and in all */
    @GetMapping("/summary")
    @PreAuthorize(Operations.READINESS_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String type, @RequestParam(required = false) String course,
                                @RequestParam(required = false) String rule, @RequestParam(defaultValue = "faculty") String by) {
        String grouping = BY.contains(by) ? by : "faculty";
        Filter f = filter(session, semester, fac, dept, prog, level, type, course, rule, null);
        generic();
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                SELECT * FROM reporting.exam_readiness_summary(CAST(:s AS text), CAST(:sem AS int), CAST(:f AS text), CAST(:d AS text),
                       CAST(:p AS text), CAST(:l AS int), CAST(:t AS text), CAST(:c AS text), CAST(:rule AS text), CAST(:by AS text))
                """).param("by", grouping), f).query().listOfRows();
        Map<String, Object> total = new LinkedHashMap<>();
        total.put("key", "ALL");
        total.put("label", "Total");
        for (String k : List.of("total", "paid_registered", "paid_not_registered", "not_paid", "not_paid_registered", "no_fee_stated", "part_paid",
                "exam_cards", "exceptions")) {
            total.put(k, rows.stream().mapToLong(r -> ((Number) r.get(k)).longValue()).sum());
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("filters", f.words());
        out.put("scope", ops.words(f.bound()));
        out.put("by", grouping);
        out.put("rows", rows);
        out.put("total", total);
        out.put("at", Instant.now());
        ops.log("RUN", "EXAM_READINESS", "Examination readiness summary by " + grouping, f.words(), ops.words(f.bound()), rows.size(), null, "SCREEN", null);
        return out;
    }

    private static String category(String cat) {
        return switch (cat) {
            case "PAID_REGISTERED", "PAID_NOT_REGISTERED", "NOT_PAID", "NO_FEE_STATED" -> " AND r.readiness = CAST(:cat AS text)";
            case "NOT_PAID_REGISTERED" -> " AND r.readiness = 'NOT_PAID' AND r.registered";
            case "EXAM_CARD" -> " AND r.exam_card";
            case "EXCEPTIONS" -> " AND r.exception IS NOT NULL AND r.exception <> 'PART_PAYMENT'";
            case "PART_PAID" -> " AND r.paid AND r.fee_status = 'PART_PAYMENT'";
            default -> "";
        };
    }

    /** the students a figure counts, names A to Z unless another order is asked for, a page at a time (or every row, for an export) */
    @GetMapping("/students")
    @PreAuthorize(Operations.READINESS_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                 @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                 @RequestParam(required = false) String type, @RequestParam(required = false) String course,
                                 @RequestParam(required = false) String rule, @RequestParam(defaultValue = "ALL") String category,
                                 @RequestParam(required = false) String astatus, @RequestParam(required = false) String exception,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "name") String sort,
                                 @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size) {
        String cat = CATEGORIES.contains(category.toUpperCase()) ? category.toUpperCase() : "ALL";
        Filter f = filter(session, semester, fac, dept, prog, level, type, course, rule, astatus);
        int sz = Math.max(1, Math.min(size, 60000));
        int pg = Math.max(1, page);
        String ex = blank(exception) == null ? null : exception.trim().toUpperCase();
        if (ex != null && !ex.matches("[A-Z_]{3,60}")) ex = null;
        String like = blank(q) == null ? null : "%" + q.trim().toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        generic();
        List<Map<String, Object>> rows = bind(jdbc.sql("SELECT r.*, count(*) OVER () AS total_rows " + ROWS + " WHERE true" + category(cat) + """
                   AND (CAST(:astatus AS text) IS NULL OR r.academic_status = CAST(:astatus AS text))
                   AND (CAST(:ex AS text) IS NULL OR r.exception = CAST(:ex AS text))
                   AND (CAST(:q AS text) IS NULL OR lower(concat_ws(' ', r.surname, r.other_names, r.matric_no, r.jamb_no)) LIKE CAST(:q AS text))
                 ORDER BY """ + " " + SORTS.getOrDefault(sort, SORTS.get("name")) + " LIMIT CAST(:n AS int) OFFSET CAST(:o AS int)")
                .param("cat", cat).param("ex", ex, Types.VARCHAR).param("q", like, Types.VARCHAR).param("n", sz).param("o", (pg - 1) * sz), f)
                .query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        boolean amounts = Operations.amounts();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total_rows");
            if (!amounts) {
                m.put("payable", null);
                m.put("paid_amount", null);
                m.put("outstanding", null);
                m.put("last_paid_at", null);
            }
            out.add(m);
        }
        if (pg == 1) {
            Map<String, Object> def = f.words();
            def.put("category", cat);
            if (ex != null) def.put("exception", ex);
            ops.log("RUN", "EXAM_READINESS", "Examination readiness: " + cat, def, ops.words(f.bound()), (int) total, null, "SCREEN", null);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("filters", f.words());
        res.put("scope", ops.words(f.bound()));
        res.put("category", cat);
        res.put("rows", out);
        res.put("total", total);
        res.put("page", pg);
        res.put("size", sz);
        res.put("amounts", amounts);
        res.put("at", Instant.now());
        return res;
    }

    /** each course a faculty or department offers in the semester — registered, paid, not paid, expected and not registered — for the
     *  students of the scope */
    @GetMapping("/courses")
    @PreAuthorize(Operations.READINESS_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> courses(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String rule, @RequestParam(required = false) String cfac,
                                @RequestParam(required = false) String cdept, @RequestParam(defaultValue = "false") boolean all) {
        Filter f = filter(session, semester, fac, dept, prog, level, null, null, rule, null);
        String cf = blank(cfac);
        String cd = blank(cdept);
        if (cf == null && cd == null && !all) {
            throw new DomainRuleViolation("READINESS_COURSE_DEPARTMENT", "Choose the faculty or department whose courses to count.",
                    new DomainRuleViolation.Remedy("Pick the department that offers the courses.", "You"));
        }
        generic();
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                SELECT * FROM reporting.course_readiness_summary(CAST(:s AS text), CAST(:sem AS int), CAST(:f AS text), CAST(:d AS text),
                       CAST(:p AS text), CAST(:cf AS text), CAST(:cd AS text), CAST(:l AS int), CAST(:rule AS text))
                """).param("cf", cf, Types.VARCHAR).param("cd", cd, Types.VARCHAR), f).query().listOfRows();
        Map<String, Object> def = f.words();
        if (cf != null) def.put("courseFaculty", cf);
        if (cd != null) def.put("courseDepartment", cd);
        ops.log("RUN", "EXAM_READINESS", "Course readiness summary", def, ops.words(f.bound()), rows.size(), null, "SCREEN", null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("filters", def);
        out.put("scope", ops.words(f.bound()));
        out.put("rows", rows);
        out.put("at", Instant.now());
        return out;
    }

    /** the courses offered in the semester, of a faculty or department, to choose one from */
    @GetMapping("/courses/options")
    @PreAuthorize(Operations.READINESS_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courseOptions(@RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                            @RequestParam(required = false) String cfac, @RequestParam(required = false) String cdept) {
        Filter f = filter(session, semester, null, null, null, null, null, null, null, null);
        return jdbc.sql("""
                SELECT DISTINCT c.code, c.title, c.units, c.level, c.dept_code, d.name AS department
                  FROM catalogue.offering o
                  JOIN catalogue.course c ON c.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE o.session = :s AND o.semester = :sem
                   AND (CAST(:cf AS text) IS NULL OR d.faculty_code = CAST(:cf AS text))
                   AND (CAST(:cd AS text) IS NULL OR c.dept_code = CAST(:cd AS text))
                 ORDER BY c.code
                 LIMIT 3000
                """).param("s", f.session()).param("sem", f.semester()).param("cf", blank(cfac), Types.VARCHAR).param("cd", blank(cdept), Types.VARCHAR)
                .query().listOfRows();
    }

    public record Package(@Size(max = 9) String session, Integer semester, @Size(max = 20) String fac, @Size(max = 20) String dept,
                          @Size(max = 20) String prog, Integer level, @Size(max = 30) String type, @Size(max = 30) String course,
                          @Size(max = 10) String rule, @Size(max = 300) String title) {
    }

    /**
     * The examination readiness report package: one official reference (DBO/EXAM/YYYY/NNNNNN) for its six reports — paid and
     * registered, paid but not registered, not paid, course-level registration, the department summary and the faculty summary —
     * with the filters, the scope and the figures as they stood when it was issued; the reports are drawn with the same filters.
     */
    @PostMapping("/package")
    @PreAuthorize(Operations.READINESS_READERS)
    @Transactional
    Map<String, Object> issue(@Valid @RequestBody Package body) {
        Filter f = filter(body.session(), body.semester(), body.fac(), body.dept(), body.prog(), body.level(), body.type(), body.course(), body.rule(), null);
        generic();
        Map<String, Object> figures = bind(jdbc.sql("""
                SELECT total, paid_registered, paid_not_registered, not_paid, not_paid_registered, no_fee_stated, part_paid, exam_cards, exceptions
                  FROM reporting.exam_readiness_summary(CAST(:s AS text), CAST(:sem AS int), CAST(:f AS text), CAST(:d AS text),
                       CAST(:p AS text), CAST(:l AS int), CAST(:t AS text), CAST(:c AS text), CAST(:rule AS text), 'all')
                """), f).query().listOfRows().stream().findFirst().orElseGet(() -> {
                    Map<String, Object> z = new LinkedHashMap<>();
                    for (String k : List.of("total", "paid_registered", "paid_not_registered", "not_paid", "not_paid_registered", "no_fee_stated",
                            "part_paid", "exam_cards", "exceptions")) z.put(k, 0);
                    return z;
                });
        String words = ops.words(f.bound());
        String sem = switch (f.semester()) { case 1 -> "First"; case 2 -> "Second"; default -> "Third"; };
        String title = blank(body.title()) != null ? body.title().trim()
                : "Examination readiness — " + f.session() + " " + sem + " Semester — " + words;
        String ref = jdbc.sql("SELECT reporting.issue_report('EXAM', :t, CAST(:fl AS jsonb), :sc, CAST(:fg AS jsonb), :n, CAST(:parts AS jsonb))")
                .param("t", title).param("fl", Operations.json(f.words())).param("sc", words).param("fg", Operations.json(figures))
                .param("n", ((Number) figures.get("total")).intValue()).param("parts", Operations.json(PARTS)).query(String.class).single();
        ops.log("ISSUE", "EXAM_READINESS", title, f.words(), words, ((Number) figures.get("total")).intValue(), ref, null, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("reference", ref);
        out.put("title", title);
        out.put("generatedAt", Instant.now());
        out.put("filters", f.words());
        out.put("scope", words);
        out.put("figures", figures);
        out.put("parts", PARTS);
        return out;
    }

    public record Logged(@NotBlank @Size(max = 10) String action, @Size(max = 300) String title, Integer rows, @Size(max = 40) String reference,
                         @Size(max = 10) String format, Map<String, Object> filters) {
    }

    /** an export or print of a readiness report, on the query log with its reference (the export log keeps its own line too) */
    @PostMapping("/log")
    @PreAuthorize(Operations.READINESS_READERS)
    Map<String, Object> logged(@Valid @RequestBody Logged body) {
        String action = "PRINT".equalsIgnoreCase(body.action()) ? "PRINT" : "EXPORT";
        String fmt = body.format() == null ? null : body.format().toUpperCase();
        if (fmt != null && !Set.of("XLSX", "PDF", "PRINT").contains(fmt)) fmt = null;
        Map<String, Object> filters = body.filters() == null ? Map.of() : body.filters();
        if (filters.size() > 30) filters = Map.of();
        ops.log(action, "EXAM_READINESS", body.title(), filters, null, body.rows(), body.reference(), fmt, null);
        return Map.of("logged", true);
    }
}
