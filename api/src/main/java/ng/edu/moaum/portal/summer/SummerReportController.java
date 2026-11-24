package ng.edu.moaum.portal.summer;

import static ng.edu.moaum.portal.summer.SummerAccess.READERS;
import static ng.edu.moaum.portal.summer.SummerAccess.camel;
import static ng.edu.moaum.portal.summer.SummerAccess.nz;

import java.math.BigDecimal;
import java.nio.charset.StandardCharsets;
import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import jakarta.servlet.http.HttpServletRequest;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V779 — the Summer Semester's people and figures. The students of the Summer (those selected, those eligible, everyone) a page at a
 * time, with the figures strip; the report by faculty, department, programme, level or category with the filters the University asked
 * for (registration status, payment status, verification status, level, category); and each as a CSV. Every figure is the database's
 * (registration.summer_roster, registration.summer_report: set-based, paged, never a row per student read into the server); a Head of
 * Department is held to the department and a Dean to the faculty by the server, whatever the request names.
 */
@RestController
class SummerReportController {

    private static final int EXPORT_ROWS = 100_000;
    private static final List<String> GROUPS = List.of("ALL", "FACULTY", "DEPARTMENT", "PROGRAMME", "LEVEL", "CATEGORY");

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    SummerReportController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static long num(Object o) {
        return o == null ? 0 : ((Number) o).longValue();
    }

    private static BigDecimal money(Object o) {
        return o == null ? BigDecimal.ZERO : o instanceof BigDecimal b ? b : new BigDecimal(String.valueOf(o));
    }

    /** what the roster and the report are asked: the unit the server holds the office to, and the filters */
    private record Ask(OfficeScope.Bound b, Integer level, String category, String pay, String reg, String scopeKind, String q) {
    }

    private Ask ask(String faculty, String dept, String programme, Integer level, String category, String pay, String reg, String scopeKind, String q) {
        OfficeScope.Bound b = SummerAccess.readerBound(scope, faculty, dept, programme);
        String sk = SummerAccess.up(scopeKind);
        return new Ask(b, level, SummerAccess.up(category), SummerAccess.up(pay), SummerAccess.up(reg), sk == null ? "SELECTED" : sk, nz(q));
    }

    private Map<String, Object> period(String session) {
        return jdbc.sql("""
                SELECT p.*, registration.summer_open(p.session) AS open_now,
                       (SELECT e.id FROM assessment.exam_session e WHERE e.session = p.session AND e.semester = 3 AND e.kind = 'MAIN' AND e.stream = 'REGULAR') AS exam_session_id,
                       (SELECT e.state FROM assessment.exam_session e WHERE e.session = p.session AND e.semester = 3 AND e.kind = 'MAIN' AND e.stream = 'REGULAR') AS exam_state
                  FROM registration.summer_period p WHERE p.session = :s
                """).param("s", session).query().listOfRows().stream().findFirst().orElse(null);
    }

    /** the roster's rows for the asking: a page (limit, offset) of one statement over the Summer's students */
    private JdbcClient.StatementSpec roster(String s, Ask a, int limit, int offset) {
        return jdbc.sql("SELECT * FROM registration.summer_roster(:s, :fac, :dept, :prog, :level, :cat, :pay, :reg, :scope, :q, :limit, :offset)")
                .param("s", s).param("fac", a.b().fac(), Types.VARCHAR).param("dept", a.b().dept(), Types.VARCHAR).param("prog", a.b().prog(), Types.VARCHAR)
                .param("level", a.level(), Types.INTEGER).param("cat", a.category(), Types.VARCHAR).param("pay", a.pay(), Types.VARCHAR)
                .param("reg", a.reg(), Types.VARCHAR).param("scope", a.scopeKind()).param("q", a.q(), Types.VARCHAR)
                .param("limit", limit).param("offset", offset);
    }

    /** the report's rows for the asking, grouped as asked; `state` limits the selection-based figures */
    private List<Map<String, Object>> report(String s, String group, Ask a, String state) {
        return jdbc.sql("SELECT * FROM registration.summer_report(:s, :g, :fac, :dept, :prog, :level, :cat, :state, :pay, :reg)")
                .param("s", s).param("g", group).param("fac", a.b().fac(), Types.VARCHAR).param("dept", a.b().dept(), Types.VARCHAR)
                .param("prog", a.b().prog(), Types.VARCHAR).param("level", a.level(), Types.INTEGER).param("cat", a.category(), Types.VARCHAR)
                .param("state", state, Types.VARCHAR).param("pay", a.pay(), Types.VARCHAR).param("reg", a.reg(), Types.VARCHAR).query().listOfRows();
    }

    private static Map<String, Object> filtersOf(String s, Ask a, String extraKey, String extra) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("session", s);
        if (a.b().fac() != null) m.put("faculty", a.b().fac());
        if (a.b().dept() != null) m.put("dept", a.b().dept());
        if (a.b().prog() != null) m.put("programme", a.b().prog());
        if (a.level() != null) m.put("level", a.level());
        if (a.category() != null) m.put("category", a.category());
        if (a.pay() != null) m.put("pay", a.pay());
        if (a.reg() != null) m.put("reg", a.reg());
        if (a.q() != null) m.put("q", a.q());
        if (extra != null) m.put(extraKey, extra);
        return m;
    }

    /* ── the students ── */

    /** the Summer's students a page at a time — those with a selection or a charge (the default), the eligible, or everyone known —
     *  with the figures strip, and the paid courses the registration could not take; a HOD sees the department's, a Dean the
     *  faculty's. V779 replaces V735's whole-list read, which filtered and summed in the server and read each student's carry-overs
     *  (about 455 students then, about 19,000 now) */
    @GetMapping("/api/v1/summer/{session}/{year}/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@PathVariable String session, @PathVariable String year,
                                 @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                 @RequestParam(required = false) Integer level, @RequestParam(required = false) String category, @RequestParam(required = false) String pay,
                                 @RequestParam(required = false) String reg, @RequestParam(name = "scope", required = false) String scopeKind,
                                 @RequestParam(required = false) String q, @RequestParam(required = false) Integer page, @RequestParam(required = false) Integer size) {
        String s = session + "/" + year;
        Ask a = ask(faculty, dept, programme, level, category, pay, reg, scopeKind, q);
        SummerAccess.noJit(jdbc);
        int n = SummerAccess.size(size, 50, 200);
        int p = SummerAccess.page(page);
        List<Map<String, Object>> rows = roster(s, a, n, p * n).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("period", period(s));
        out.put("identifiedAt", jdbc.sql("SELECT max(evaluated_at) FROM registration.summer_candidate WHERE session = :s").param("s", s).query().singleRow().get("max"));
        out.put("total", rows.isEmpty() ? 0 : num(rows.get(0).get("total")));
        out.put("page", p);
        out.put("size", n);
        out.put("rows", rows);
        // V739: the paid courses the registration could not take, for the Academic Office to put right and retry
        OfficeScope.Bound b = a.b();
        out.put("issues", jdbc.sql("""
                SELECT i.id, i.student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name,
                       i.course_code, i.error, i.raised_at, pr.reference, st.programme_code, d.code AS dept_code, d.faculty_code
                  FROM registration.summer_issue i JOIN people.student st ON st.id = i.student_id
                  LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN finance.payment_reference pr ON pr.id = i.reference_id
                 WHERE i.session = :s AND i.resolved_at IS NULL ORDER BY i.raised_at
                """).param("s", s).query().listOfRows().stream()
                .filter(r -> SummerAccess.within(b, r.get("faculty_code"), r.get("dept_code"), r.get("programme_code"))).toList());
        out.put("summary", summary(s, a));
        return out;
    }

    /** the figures strip: the ALL row of the report for the same asking, in camelCase, with the names V735's summary used where the
     *  figure survives (commenced, completed, owing, paid, registeredCourses, feesOutstanding), and the money and the results of the
     *  roster's own rows added up (what the report does not group) */
    private Map<String, Object> summary(String s, Ask a) {
        List<Map<String, Object>> all = report(s, "ALL", a, null);
        Map<String, Object> r = all.isEmpty() ? Map.of() : all.get(0);
        Map<String, Object> m = new LinkedHashMap<>(camel(r));
        m.remove("groupCode");
        m.remove("groupName");
        m.put("commenced", num(r.get("students_selected")));
        m.put("completed", num(r.get("registered_students")));
        m.put("owing", num(r.get("students_unpaid")) + num(r.get("students_part_paid")));
        m.put("paid", num(r.get("students_paid")));
        m.put("registeredCourses", num(r.get("registered_courses")));
        m.put("feesOutstanding", money(r.get("fees_due")));
        Map<String, Object> sums = jdbc.sql("""
                SELECT coalesce(sum(r.programme_fee_paid), 0) AS programme_fees_paid, coalesce(sum(r.course_fees_paid), 0) AS course_fees_paid,
                       coalesce(sum(r.results_published), 0) AS results_published, coalesce(sum(r.results_passed), 0) AS results_passed,
                       coalesce(sum(r.results_failed), 0) AS results_failed
                  FROM registration.summer_roster(:s, :fac, :dept, :prog, :level, :cat, :pay, :reg, 'SELECTED', NULL, 1000000, 0) r
                """).param("s", s).param("fac", a.b().fac(), Types.VARCHAR).param("dept", a.b().dept(), Types.VARCHAR).param("prog", a.b().prog(), Types.VARCHAR)
                .param("level", a.level(), Types.INTEGER).param("cat", a.category(), Types.VARCHAR).param("pay", a.pay(), Types.VARCHAR)
                .param("reg", a.reg(), Types.VARCHAR).query().singleRow();
        m.put("programmeFeesPaid", money(sums.get("programme_fees_paid")));
        m.put("courseFeesPaid", money(sums.get("course_fees_paid")));
        m.put("resultsPublished", num(sums.get("results_published")));
        m.put("resultsPassed", num(sums.get("results_passed")));
        m.put("resultsFailed", num(sums.get("results_failed")));
        return m;
    }

    private static final Map<String, String> PAYMENT = Map.of("NOT_STARTED", "Not started", "UNPAID", "Unpaid", "PART_PAID", "Part paid", "PAID", "Paid");

    /** the roster for the filters as a spreadsheet's CSV (at most 100,000 rows), recorded on the export log in the same transaction */
    @GetMapping("/api/v1/summer/{session}/{year}/students/export")
    @PreAuthorize(READERS)
    @Transactional
    ResponseEntity<byte[]> exportStudents(@PathVariable String session, @PathVariable String year, HttpServletRequest request,
                                          @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                          @RequestParam(required = false) Integer level, @RequestParam(required = false) String category, @RequestParam(required = false) String pay,
                                          @RequestParam(required = false) String reg, @RequestParam(name = "scope", required = false) String scopeKind,
                                          @RequestParam(required = false) String q) {
        String s = session + "/" + year;
        Ask a = ask(faculty, dept, programme, level, category, pay, reg, scopeKind, q);
        SummerAccess.noJit(jdbc);
        SummerAccess.Csv csv = new SummerAccess.Csv("Matriculation number", "Name", "Faculty", "Department", "Programme", "Level", "Summer level", "Category",
                "Eligible", "Reason", "Results on the portal", "Courses selected", "Pending verification", "Confirmed outstanding", "Not outstanding", "Rejected",
                "Needs review", "Questions to the student", "Courses paid", "Units", "Programme fee due", "Programme fee paid", "Course fees due", "Course fees paid",
                "Payment", "Registration", "Courses registered", "Results published", "Results passed", "Results failed");
        roster(s, a, EXPORT_ROWS, 0).query((RowCallbackHandler) rs -> {
            String pay1 = rs.getString("payment_state");
            csv.row(rs.getString("matric_no"), rs.getString("name"), rs.getString("faculty"), rs.getString("department"), rs.getString("programme"),
                    rs.getObject("level"), rs.getObject("summer_level"), rs.getString("category"), rs.getBoolean("eligible") ? "Yes" : "No", rs.getString("reason"),
                    rs.getObject("results"), rs.getObject("selected"), rs.getObject("pending"), rs.getObject("confirmed"), rs.getObject("not_outstanding"),
                    rs.getObject("rejected"), rs.getObject("flagged"), rs.getObject("clarifications"), rs.getObject("courses_paid"), rs.getObject("units"),
                    rs.getBigDecimal("programme_fee_due"), rs.getBigDecimal("programme_fee_paid"), rs.getBigDecimal("course_fees_due"), rs.getBigDecimal("course_fees_paid"),
                    pay1 == null ? "" : PAYMENT.getOrDefault(pay1, pay1), rs.getString("registration_status"), rs.getObject("courses_registered"),
                    rs.getObject("results_published"), rs.getObject("results_passed"), rs.getObject("results_failed"));
        });
        jdbc.sql("SELECT platform.log_export(:r, 'CSV', :n, CAST(:f AS jsonb), :s, NULL)")
                .param("r", "Summer students").param("n", csv.rows())
                .param("f", SummerAccess.JSON.writeValueAsString(filtersOf(s, a, "scope", a.scopeKind()))).param("s", request.getRequestURI())
                .query(Object.class).single();
        return file(csv, "summer-" + SummerAccess.fileSession(s) + "-students.csv");
    }

    /* ── the report ── */

    /** the figures the University asked for — eligible, missing historical results, selected, pending, confirmed, not outstanding or
     *  rejected, registered, by payment and registration status, fees paid and still to pay, credits open — overall or by faculty,
     *  department, programme, level or category, within the caller's unit */
    @GetMapping("/api/v1/summer/{session}/{year}/report")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> report(@PathVariable String session, @PathVariable String year, @RequestParam(required = false) String group,
                               @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                               @RequestParam(required = false) Integer level, @RequestParam(required = false) String category, @RequestParam(required = false) String state,
                               @RequestParam(required = false) String pay, @RequestParam(required = false) String reg) {
        String s = session + "/" + year;
        String g = group(group);
        Ask a = ask(faculty, dept, programme, level, category, pay, reg, null, null);
        List<Map<String, Object>> rows = report(s, g, a, SummerAccess.up(state)).stream().map(SummerAccess::camel).toList();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("group", g);
        out.put("rows", rows);
        Map<String, Object> sc = new LinkedHashMap<>();
        sc.put("office", SummerAccess.office());
        sc.put("faculty", a.b().fac());
        sc.put("dept", a.b().dept());
        out.put("scope", sc);
        out.put("at", java.time.Instant.now().toString());
        return out;
    }

    private static String group(String group) {
        String g = group == null || group.isBlank() ? "ALL" : group.trim().toUpperCase();
        if (!GROUPS.contains(g)) {
            throw new DomainRuleViolation("SUMMER_REPORT_GROUP", "The report is grouped by one of " + String.join(", ", GROUPS) + ".",
                    new DomainRuleViolation.Remedy("Choose how to group the report.", "You"));
        }
        return g;
    }

    /** the report as a CSV, recorded on the export log in the same transaction */
    @GetMapping("/api/v1/summer/{session}/{year}/report/export")
    @PreAuthorize(READERS)
    @Transactional
    ResponseEntity<byte[]> exportReport(@PathVariable String session, @PathVariable String year, HttpServletRequest request,
                                        @RequestParam(required = false) String group,
                                        @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                        @RequestParam(required = false) Integer level, @RequestParam(required = false) String category, @RequestParam(required = false) String state,
                                        @RequestParam(required = false) String pay, @RequestParam(required = false) String reg) {
        String s = session + "/" + year;
        String g = group(group);
        Ask a = ask(faculty, dept, programme, level, category, pay, reg, null, null);
        List<Map<String, Object>> rows = report(s, g, a, SummerAccess.up(state));
        SummerAccess.Csv csv = new SummerAccess.Csv("Group", "Name", "Eligible", "Eligible final-year", "Eligible spillover", "Eligible authorised",
                "Students with missing historical results", "Students who selected", "Courses selected", "Pending verification", "Confirmed outstanding",
                "Not outstanding", "Rejected", "Questions to students", "Needs review", "Students registered", "Courses registered", "Units selected",
                "Students not started", "Students unpaid", "Students part paid", "Students paid", "Fees paid", "Outstanding Summer payments", "Credits open",
                "Selections with no result");
        for (Map<String, Object> r : rows) {
            csv.row(r.get("group_code"), r.get("group_name"), r.get("eligible"), r.get("eligible_final_year"), r.get("eligible_spillover"), r.get("eligible_authorised"),
                    r.get("missing_history_students"), r.get("students_selected"), r.get("courses_selected"), r.get("pending"), r.get("confirmed"),
                    r.get("not_outstanding"), r.get("rejected"), r.get("clarifications"), r.get("flagged"), r.get("registered_students"), r.get("registered_courses"),
                    r.get("units_selected"), r.get("students_not_started"), r.get("students_unpaid"), r.get("students_part_paid"), r.get("students_paid"),
                    r.get("fees_paid"), r.get("fees_due"), r.get("credits_open"), r.get("selections_no_result"));
        }
        Map<String, Object> filters = filtersOf(s, a, "group", g);
        if (SummerAccess.up(state) != null) filters.put("state", SummerAccess.up(state));
        jdbc.sql("SELECT platform.log_export(:r, 'CSV', :n, CAST(:f AS jsonb), :s, NULL)")
                .param("r", "Summer report").param("n", csv.rows())
                .param("f", SummerAccess.JSON.writeValueAsString(filters)).param("s", request.getRequestURI())
                .query(Object.class).single();
        return file(csv, "summer-" + SummerAccess.fileSession(s) + "-report.csv");
    }

    private static ResponseEntity<byte[]> file(SummerAccess.Csv csv, String name) {
        return ResponseEntity.ok().contentType(new MediaType("text", "csv", StandardCharsets.UTF_8))
                .header(HttpHeaders.CONTENT_DISPOSITION, "attachment; filename=\"" + name + "\"")
                .header("Cache-Control", "no-store").body(csv.bytes());
    }
}
