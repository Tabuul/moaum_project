package ng.edu.moaum.portal.analytics;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.stats.AnalyticsScope;
import ng.edu.moaum.portal.stats.AnalyticsScope.Bound;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * Financial analytics (V279): one engine over reporting.payments — every confirmed
 * payment the portal generated, in its category, with the payer's faculty, department,
 * programme, level, sex, entry mode and session. The summary answers how much was
 * received, in how many transactions, from how many distinct payers — in all and by
 * category, faculty, department, programme, level, gender, entry mode, session and
 * channel, with the trend by day, week, month, quarter or year and the same figures
 * for the period before; the transactions list pages the very rows a figure counted.
 * The scope is the acting office's, held on the server (AnalyticsScope); the
 * transactions and the export open only to the offices that hold the purse.
 * Revenue is a confirmed reference of a category that counts as revenue — never a
 * sum of every row; a failed gateway attempt, a pending reference and a paid refund
 * are counted apart.
 */
@RestController
@RequestMapping("/api/v1/analytics")
class FinancialAnalyticsController {

    private static final String SUMMARY_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_admin',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_provost','OFFICE_collegesecretary','OFFICE_dvc','OFFICE_vc','OFFICE_audit',"
            + "'OFFICE_ict','OFFICE_dean','OFFICE_facultyofficer')";   // the Head of Department and the Academic Office no longer read finance (Oct 2026)
    private static final String TRANSACTION_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_admin',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_provost','OFFICE_collegesecretary','OFFICE_dvc','OFFICE_vc','OFFICE_audit',"
            + "'OFFICE_dean','OFFICE_facultyofficer')";
    private static final String CATEGORY_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    private static final Set<String> GRANULARITY = Set.of("day", "week", "month", "quarter", "year");
    private static final Set<String> FAILED = Set.of("NOT_SUCCESSFUL", "SHORT_PAID", "BAD_SIGNATURE", "GATEWAY_ERROR", "UNKNOWN_REFERENCE");

    private final JdbcClient jdbc;
    private final AnalyticsScope scope;

    FinancialAnalyticsController(JdbcClient jdbc, AnalyticsScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the filters, each applied only within the bound */
    record Filters(LocalDate from, LocalDate to, String types, String sex, String fac, String dept, String prog, Integer level,
                   String session, String entry, String channel, String q, String granularity) {
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private Filters filters(String from, String to, String types, String sex, String fac, String dept, String prog, Integer level,
                            String session, String entry, String channel, String q, String granularity) {
        LocalDate f = parseDate(from), t = parseDate(to);
        if (f != null && t != null && t.isBefore(f)) { LocalDate x = f; f = t; t = x; }
        String sx = sex == null ? null : sex.trim().toUpperCase();
        String ty = types == null ? null : String.join(",", java.util.Arrays.stream(types.split(",")).map(String::trim).filter(x -> x.matches("[A-Z][A-Z0-9_]{1,39}")).toList());
        // the default is the current session (the portal's convention); "ALL" opens every session, and a date window
        // or a search (a reference, a receipt, a name) stands on its own across every session
        String ses = session != null && session.matches("\\d{4}/\\d{4}") ? session
                : session != null && session.equalsIgnoreCase("ALL") ? null
                : f == null && t == null && (q == null || q.isBlank()) ? currentSession() : null;
        return new Filters(f, t, ty == null || ty.isEmpty() ? null : ty, "M".equals(sx) || "F".equals(sx) ? sx : null,
                blank(fac), blank(dept), blank(prog), level, ses,
                blank(entry) == null ? null : entry.trim().toUpperCase(), blank(channel),
                q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%",
                granularity != null && GRANULARITY.contains(granularity.toLowerCase()) ? granularity.toLowerCase() : "day");
    }

    private String currentSession() {
        return jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse(null);
    }

    private static LocalDate parseDate(String s) {
        if (s == null || s.isBlank()) return null;
        try {
            return LocalDate.parse(s.trim());
        } catch (java.time.format.DateTimeParseException e) {
            throw new DomainRuleViolation("ANALYTICS_DATE", "'" + s + "' is not a date.", new DomainRuleViolation.Remedy("Dates are YYYY-MM-DD.", "You"));
        }
    }

    /* ── the rows: the ledger within the bound and the filters ── */

    private static final String ROWS = """
            SELECT v.*, coalesce(c.label, v.category_code) AS category, coalesce(c.revenue, true) AS revenue
              FROM reporting.payments v LEFT JOIN finance.payment_category c ON c.code = v.category_code
             WHERE (:pg::boolean IS NULL OR v.is_pg = :pg)
               AND (:chs::boolean IS NULL OR v.is_chs = :chs)
               AND (:bf::text IS NULL OR v.faculty_code = :bf)
               AND (:bd::text IS NULL OR v.dept_code = :bd)
               AND (:types::text IS NULL OR v.category_code = ANY (string_to_array(:types, ',')))
               AND (:sex::text IS NULL OR v.sex = :sex)
               AND (:fac::text IS NULL OR v.faculty_code = :fac)
               AND (:dept::text IS NULL OR v.dept_code = :dept)
               AND (:prog::text IS NULL OR v.programme_code = :prog)
               AND (:level::int IS NULL OR v.level = :level)
               AND (:session::text IS NULL OR v.session = :session)
               AND (:entry::text IS NULL OR v.entry_mode = :entry)
               AND (:channel::text IS NULL OR v.channel = :channel)
               AND (:q::text IS NULL OR lower(v.reference) LIKE :q OR lower(coalesce(v.number, '')) LIKE :q OR lower(coalesce(v.receipt_no, '')) LIKE :q
                    OR lower(v.surname || ' ' || coalesce(v.other_names, '')) LIKE :q OR lower(coalesce(v.other_names, '') || ' ' || v.surname) LIKE :q)
            """;
    /** revenue: confirmed, in the window, of a category that counts */
    private static final String CONFIRMED = " AND v.confirmed_at IS NOT NULL AND coalesce(c.revenue, true)"
            + " AND (:from::date IS NULL OR v.confirmed_at >= :from::date) AND (:to::date IS NULL OR v.confirmed_at < (:to::date + 1))";

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec q, Bound b, Filters f, LocalDate from, LocalDate to) {
        return q.param("pg", b.pg() ? Boolean.TRUE : null, Types.BOOLEAN).param("chs", b.chs() ? Boolean.TRUE : null, Types.BOOLEAN)
                .param("bf", b.faculty(), Types.VARCHAR).param("bd", b.dept(), Types.VARCHAR)
                .param("types", f.types(), Types.VARCHAR).param("sex", f.sex(), Types.VARCHAR)
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("level", f.level(), Types.INTEGER).param("session", f.session(), Types.VARCHAR).param("entry", f.entry(), Types.VARCHAR)
                .param("channel", f.channel(), Types.VARCHAR).param("q", f.q(), Types.VARCHAR)
                .param("from", from, Types.DATE).param("to", to, Types.DATE);
    }

    /* ── the summary ── */

    @GetMapping("/finance/summary")
    @PreAuthorize(SUMMARY_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String from, @RequestParam(required = false) String to,
                                @RequestParam(required = false) String types, @RequestParam(required = false) String sex,
                                @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                @RequestParam(required = false) String session, @RequestParam(required = false) String entry,
                                @RequestParam(required = false) String channel, @RequestParam(required = false) String q,
                                @RequestParam(required = false) String granularity, @RequestParam(defaultValue = "true") boolean compare) {
        Bound b = scope.bound();
        Filters f = filters(from, to, types, sex, fac, dept, prog, level, session, entry, channel, q, granularity);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("scope", scopeOf(b));
        out.put("filters", filterMap(f));
        out.put("options", options(b));
        groups(out, b, f);
        out.put("totals", totals((Map<String, Object>) out.get("totals"), b, f));
        out.put("compare", compare ? comparison(b, f) : null);
        return out;
    }

    private Map<String, Object> scopeOf(Bound b) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("kind", b.kind());
        m.put("label", b.label());
        m.put("faculty", b.faculty() == null ? "" : b.faculty());
        m.put("department", b.dept() == null ? "" : b.dept());
        m.put("money", b.money());
        m.put("transactions", scope.transactions());
        m.put("office", scope.office());
        return m;
    }

    private static Map<String, Object> filterMap(Filters f) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("from", f.from() == null ? "" : f.from().toString());
        m.put("to", f.to() == null ? "" : f.to().toString());
        m.put("types", f.types() == null ? List.of() : List.of(f.types().split(",")));
        m.put("sex", f.sex() == null ? "" : f.sex());
        m.put("fac", f.fac() == null ? "" : f.fac());
        m.put("dept", f.dept() == null ? "" : f.dept());
        m.put("prog", f.prog() == null ? "" : f.prog());
        m.put("level", f.level() == null ? "" : String.valueOf(f.level()));
        m.put("session", f.session() == null ? "" : f.session());
        m.put("entry", f.entry() == null ? "" : f.entry());
        m.put("channel", f.channel() == null ? "" : f.channel());
        m.put("q", f.q() == null ? "" : f.q().substring(1, f.q().length() - 1));
        m.put("granularity", f.granularity());
        return m;
    }

    /** one pass over the rows: the totals and every breakdown, by grouping sets */
    @SuppressWarnings("unchecked")
    private void groups(Map<String, Object> out, Bound b, Filters f) {
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + CONFIRMED + """
                ), x AS (SELECT r.*, date_trunc(:g, r.confirmed_at)::date AS bucket FROM r)
                SELECT grouping(category_code) AS g_c, grouping(faculty_code) AS g_f, grouping(dept_code) AS g_d, grouping(programme_code) AS g_p,
                       grouping(level) AS g_l, grouping(sex) AS g_s, grouping(entry_mode) AS g_e, grouping(session) AS g_ss, grouping(channel) AS g_ch, grouping(bucket) AS g_b,
                       category_code, category, faculty_code, faculty, dept_code, department, programme_code, programme, level, sex, entry_mode, session, channel, bucket,
                       count(*) AS transactions, count(DISTINCT payer_key) AS payers, coalesce(sum(amount), 0) AS amount
                  FROM x
                 GROUP BY GROUPING SETS ((), (category_code, category), (faculty_code, faculty), (faculty_code, faculty, dept_code, department),
                                         (faculty_code, faculty, dept_code, department, programme_code, programme),
                                         (level), (sex), (entry_mode), (session), (channel), (bucket))
                 ORDER BY amount DESC, category, faculty, department, programme, level, sex, entry_mode, session, channel, bucket
                """), b, f, f.from(), f.to()).param("g", f.granularity()).query().listOfRows();
        Map<String, Object> totals = null;
        List<Map<String, Object>> byCategory = new ArrayList<>(), byFaculty = new ArrayList<>(), byDepartment = new ArrayList<>(), byProgramme = new ArrayList<>(),
                byLevel = new ArrayList<>(), byGender = new ArrayList<>(), byEntry = new ArrayList<>(), bySession = new ArrayList<>(), byChannel = new ArrayList<>(), trend = new ArrayList<>();
        for (Map<String, Object> g : rows) {
            Map<String, Object> m = figures(g);
            if (flag(g, "g_b") == 0) { m.put("bucket", String.valueOf(g.get("bucket"))); trend.add(m); }
            else if (flag(g, "g_c") == 0) { m.put("code", g.get("category_code")); m.put("label", g.get("category")); byCategory.add(m); }
            else if (flag(g, "g_p") == 0) { put(m, g, "faculty_code", "faculty", "dept_code", "department", "programme_code", "programme"); byProgramme.add(m); }
            else if (flag(g, "g_d") == 0) { put(m, g, "faculty_code", "faculty", "dept_code", "department"); byDepartment.add(m); }
            else if (flag(g, "g_f") == 0) { put(m, g, "faculty_code", "faculty"); byFaculty.add(m); }
            else if (flag(g, "g_l") == 0) { m.put("level", g.get("level")); byLevel.add(m); }
            else if (flag(g, "g_s") == 0) { m.put("sex", g.get("sex")); byGender.add(m); }
            else if (flag(g, "g_e") == 0) { m.put("entry_mode", g.get("entry_mode")); byEntry.add(m); }
            else if (flag(g, "g_ss") == 0) { m.put("session", g.get("session")); bySession.add(m); }
            else if (flag(g, "g_ch") == 0) { m.put("channel", g.get("channel")); byChannel.add(m); }
            else totals = m;
        }
        if (totals == null) totals = figures(Map.of("transactions", 0L, "payers", 0L, "amount", BigDecimal.ZERO));
        trend.sort((x, y) -> String.valueOf(x.get("bucket")).compareTo(String.valueOf(y.get("bucket"))));
        bySession.sort((x, y) -> String.valueOf(y.get("session")).compareTo(String.valueOf(x.get("session"))));
        byLevel.sort((x, y) -> Integer.compare(x.get("level") == null ? 0 : ((Number) x.get("level")).intValue(), y.get("level") == null ? 0 : ((Number) y.get("level")).intValue()));
        out.put("totals", totals);
        out.put("byCategory", byCategory);
        out.put("byFaculty", byFaculty);
        out.put("byDepartment", byDepartment);
        out.put("byProgramme", byProgramme);
        out.put("byLevel", byLevel);
        out.put("byGender", byGender);
        out.put("byEntry", byEntry);
        out.put("bySession", bySession);
        out.put("byChannel", byChannel);
        out.put("trend", trend);
    }

    private static int flag(Map<String, Object> g, String k) {
        return ((Number) g.get(k)).intValue();
    }

    private static void put(Map<String, Object> m, Map<String, Object> g, String... keys) {
        for (String k : keys) m.put(k, g.get(k));
    }

    private static Map<String, Object> figures(Map<String, Object> g) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("transactions", ((Number) g.get("transactions")).longValue());
        m.put("payers", ((Number) g.get("payers")).longValue());
        m.put("amount", g.get("amount") == null ? BigDecimal.ZERO : g.get("amount"));
        return m;
    }

    /** the figures no revenue sum shows: pending references, failed gateway attempts, refunds paid */
    private Map<String, Object> totals(Map<String, Object> revenue, Bound b, Filters f) {
        Map<String, Object> t = new LinkedHashMap<>(revenue);
        t.put("revenue", revenue.get("amount"));
        Map<String, Object> pending = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + """
                ) SELECT count(*) AS n, coalesce(sum(amount), 0) AS amount FROM r v
                   WHERE v.confirmed_at IS NULL AND v.expires_at > now()
                     AND (:from::date IS NULL OR v.generated_at >= :from::date) AND (:to::date IS NULL OR v.generated_at < (:to::date + 1))
                """), b, f, f.from(), f.to()).query().singleRow();
        t.put("pending_count", pending.get("n"));
        t.put("pending_amount", pending.get("amount"));
        Map<String, Object> failed = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + """
                ) SELECT count(*) AS n FROM finance.gateway_event e JOIN r v ON v.reference = e.reference
                   WHERE e.outcome = ANY (string_to_array(:failed, ','))
                     AND (:from::date IS NULL OR e.received_at >= :from::date) AND (:to::date IS NULL OR e.received_at < (:to::date + 1))
                """), b, f, f.from(), f.to()).param("failed", String.join(",", FAILED)).query().singleRow();
        t.put("failed_count", failed.get("n"));
        Map<String, Object> refunds = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + """
                ) SELECT count(*) AS n, coalesce(sum(rf.amount), 0) AS amount FROM finance.refund rf JOIN r v ON v.reference = rf.reference
                   WHERE rf.state = 'PAID'
                     AND (:from::date IS NULL OR rf.paid_at >= :from::date) AND (:to::date IS NULL OR rf.paid_at < (:to::date + 1))
                """), b, f, f.from(), f.to()).query().singleRow();
        t.put("refunded_count", refunds.get("n"));
        t.put("refunded_amount", refunds.get("amount"));
        t.put("net_revenue", ((BigDecimal) t.get("revenue")).subtract((BigDecimal) refunds.get("amount")));
        return t;
    }

    /** the period before: the same length of days before the window, or the session before the session asked for */
    private Map<String, Object> comparison(Bound b, Filters f) {
        LocalDate from = f.from(), to = f.to();
        Filters prev;
        String label;
        if (from != null && to != null) {
            long days = java.time.temporal.ChronoUnit.DAYS.between(from, to) + 1;
            prev = new Filters(from.minusDays(days), from.minusDays(1), f.types(), f.sex(), f.fac(), f.dept(), f.prog(), f.level(), f.session(), f.entry(), f.channel(), f.q(), f.granularity());
            label = "Previous " + days + " day" + (days == 1 ? "" : "s");
        } else if (f.session() != null) {
            int y = Integer.parseInt(f.session().substring(0, 4)) - 1;
            String before = y + "/" + (y + 1);
            prev = new Filters(null, null, f.types(), f.sex(), f.fac(), f.dept(), f.prog(), f.level(), before, f.entry(), f.channel(), f.q(), f.granularity());
            label = "Session " + before;
        } else {
            return null;
        }
        Map<String, Object> row = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + CONFIRMED + """
                ) SELECT count(*) AS transactions, count(DISTINCT payer_key) AS payers, coalesce(sum(amount), 0) AS amount FROM r
                """), b, prev, prev.from(), prev.to()).query().singleRow();
        Map<String, Object> m = figures(row);
        m.put("label", label);
        m.put("from", prev.from() == null ? "" : prev.from().toString());
        m.put("to", prev.to() == null ? "" : prev.to().toString());
        m.put("session", prev.session() == null ? "" : prev.session());
        return m;
    }

    /** what the filter bar may offer, within the bound */
    private Map<String, Object> options(Bound b) {
        Map<String, Object> o = new LinkedHashMap<>();
        o.put("categories", jdbc.sql("SELECT code, label, ord, revenue, active FROM finance.payment_category WHERE active ORDER BY ord, code").query().listOfRows());
        o.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        o.put("currentSession", jdbc.sql("SELECT name FROM policy.academic_session WHERE state = 'CURRENT'").query(String.class).optional().orElse(null));
        o.put("entryModes", jdbc.sql("SELECT DISTINCT entry_mode FROM people.student WHERE entry_mode IS NOT NULL ORDER BY entry_mode").query(String.class).list());
        o.put("channels", jdbc.sql("SELECT channel FROM (SELECT channel FROM finance.payment_reference WHERE channel IS NOT NULL UNION SELECT channel FROM admissions.fee_reference WHERE channel IS NOT NULL) c GROUP BY channel ORDER BY channel").query(String.class).list());
        String where = switch (b.kind()) {
            case "PG_SCHOOL" -> " AND p.category = 'POST GRADUATE'";
            case "COLLEGE" -> " AND f.college_code = 'CHS'";
            case "FACULTY" -> " AND f.code = :bf";
            case "DEPARTMENT" -> " AND d.code = :bd";
            default -> "";
        };
        JdbcClient.StatementSpec q = jdbc.sql("""
                SELECT DISTINCT f.code AS faculty_code, f.name AS faculty, d.code AS dept_code, d.name AS department, p.code AS programme_code, p.name AS programme
                  FROM ref.programme p JOIN ref.faculty f ON f.code = p.faculty_code JOIN ref.department d ON d.code = p.dept_code
                 WHERE NOT p.archived""" + where + " ORDER BY f.name, d.name, p.name");
        if ("FACULTY".equals(b.kind())) q = q.param("bf", b.faculty());
        if ("DEPARTMENT".equals(b.kind())) q = q.param("bd", b.dept());
        o.put("programmes", q.query().listOfRows());
        o.put("levels", b.pg() ? List.of(700, 800, 900) : List.of(100, 200, 300, 400, 500, 600, 700, 800, 900));
        o.put("genders", List.of("M", "F"));
        o.put("granularities", List.of("day", "week", "month", "quarter", "year"));
        return o;
    }

    /* ── the transactions behind a figure ── */

    @GetMapping("/finance/transactions")
    @PreAuthorize(TRANSACTION_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> transactions(@RequestParam(required = false) String from, @RequestParam(required = false) String to,
                                     @RequestParam(required = false) String types, @RequestParam(required = false) String sex,
                                     @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                     @RequestParam(required = false) String prog, @RequestParam(required = false) Integer level,
                                     @RequestParam(required = false) String session, @RequestParam(required = false) String entry,
                                     @RequestParam(required = false) String channel, @RequestParam(required = false) String q,
                                     @RequestParam(required = false) String studentId,
                                     @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        Bound b = scope.bound();
        Filters f = filters(from, to, types, sex, fac, dept, prog, level, session, entry, channel, q, null);
        int sz = Math.max(1, Math.min(size, 500));
        int pg = Math.max(0, page);
        java.util.UUID student = null;
        if (studentId != null && !studentId.isBlank()) {
            try { student = java.util.UUID.fromString(studentId.trim()); } catch (IllegalArgumentException e) { student = new java.util.UUID(0, 0); }
        }
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + CONFIRMED + """
                )
                SELECT count(*) OVER () AS total_rows, r.source, r.reference, r.receipt_no, r.number, r.student_id, r.application_id, r.pg_application_id,
                       r.surname, r.other_names, r.sex, r.faculty_code, r.faculty, r.dept_code, r.department, r.programme_code, r.programme, r.level, r.entry_mode, r.entry_session,
                       r.session, r.category_code, r.category, r.purpose, r.kind, r.amount, r.confirmed_at, r.generated_at, r.channel, r.status
                  FROM r
                 WHERE (:student::uuid IS NULL OR r.student_id = :student)
                 ORDER BY r.confirmed_at DESC, r.reference
                 LIMIT :n OFFSET :o
                """), b, f, f.from(), f.to()).param("student", student, Types.OTHER).param("n", sz).param("o", pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> x = new LinkedHashMap<>(r);
            x.remove("total_rows");
            x.put("status", "CONFIRMED");
            out.add(x);
        }
        Map<String, Object> res = new LinkedHashMap<>();
        res.put("scope", scopeOf(b));
        res.put("filters", filterMap(f));
        res.put("total", total);
        res.put("page", pg);
        res.put("size", sz);
        res.put("rows", out);
        return res;
    }

    /* ── the categories: the Bursary's, configured ── */

    public record CategoryIn(@NotBlank @Size(max = 120) String label, List<String> kinds, @Size(max = 400) String pattern, Integer ord, Boolean revenue, Boolean active) {
    }

    @GetMapping("/finance/categories")
    @PreAuthorize(SUMMARY_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> categories() {
        return jdbc.sql("SELECT code, label, kinds, pattern, ord, revenue, active, updated_at FROM finance.payment_category ORDER BY ord, code").query().listOfRows()
                .stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.put("kinds", kinds(r.get("kinds"))); return m; }).toList();
    }

    private static List<String> kinds(Object pgArray) {
        try {
            if (pgArray instanceof java.sql.Array a) return List.of((String[]) a.getArray());
        } catch (java.sql.SQLException ignored) { /* fall through */ }
        return pgArray instanceof String[] s ? List.of(s) : List.of();
    }

    /** a category stated or amended: its label, the reference kinds and the purpose pattern that place a payment in it */
    @PutMapping("/finance/categories/{code}")
    @PreAuthorize(CATEGORY_SETTERS)
    @Transactional
    Map<String, Object> setCategory(@PathVariable String code, @Valid @RequestBody CategoryIn body) {
        String c = code == null ? "" : code.trim().toUpperCase();
        if (!c.matches("[A-Z][A-Z0-9_]{1,39}")) {
            throw new DomainRuleViolation("PAY_CATEGORY_CODE", "A category code is capital letters, digits and underscores, up to forty characters.",
                    new DomainRuleViolation.Remedy("For example GST or CONVOCATION.", "Bursary"));
        }
        AuditContextHolder.required();
        String[] kinds = body.kinds() == null ? new String[0] : body.kinds().stream().map(k -> k.trim().toUpperCase()).filter(k -> !k.isEmpty()).toArray(String[]::new);
        try {
            return jdbc.sql("SELECT code, label, kinds, pattern, ord, revenue, active, updated_at FROM finance.set_payment_category(:c, :l, :k::text[], :p, :o, :r, :a)")
                    .param("c", c).param("l", body.label().trim()).param("k", kinds).param("p", body.pattern(), Types.VARCHAR)
                    .param("o", body.ord(), Types.INTEGER).param("r", body.revenue(), Types.BOOLEAN).param("a", body.active(), Types.BOOLEAN)
                    .query().singleRow().entrySet().stream().collect(LinkedHashMap::new, (m, e) -> m.put(e.getKey(), "kinds".equals(e.getKey()) ? kinds(e.getValue()) : e.getValue()), Map::putAll);
        } catch (org.springframework.dao.DataAccessException e) {
            throw new DomainRuleViolation("PAY_CATEGORY_PATTERN", "The purpose pattern is not a regular expression the database accepts.",
                    new DomainRuleViolation.Remedy("Try a plain prefix such as ^gst", "Bursary"));
        }
    }
}
