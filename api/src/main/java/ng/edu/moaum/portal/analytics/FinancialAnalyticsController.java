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
 * are counted apart. V409: every payment also carries its programme type, purpose,
 * source module and responsible office as separate dimensions — filters and
 * breakdowns, programme type by purpose among them ("Sandwich school fees") — and the
 * offices that own a purpose (JUPEB, the Centre, GST, EPS, Housing) read their own.
 */
@RestController
@RequestMapping("/api/v1/analytics")
class FinancialAnalyticsController {

    private static final String SUMMARY_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_admin',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_provost','OFFICE_collegesecretary','OFFICE_dvc','OFFICE_vc','OFFICE_audit',"
            + "'OFFICE_ict','OFFICE_dean','OFFICE_facultyofficer',"
            + "'OFFICE_jupeb','OFFICE_cce','OFFICE_gst','OFFICE_eps','OFFICE_housing')";   // the Head of Department and the Academic Office no longer read finance (Oct 2026)
    private static final String TRANSACTION_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_admin',"
            + "'OFFICE_pgschool','OFFICE_pgsecretary','OFFICE_provost','OFFICE_collegesecretary','OFFICE_dvc','OFFICE_vc','OFFICE_audit',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_jupeb','OFFICE_cce','OFFICE_gst','OFFICE_eps','OFFICE_housing')";
    /** V409: the offices that own a purpose read the payments they own — their own, amounts and transactions, nothing else */
    private static final Set<String> OWNERS = Set.of("jupeb", "cce", "gst", "eps", "housing");
    /** V409: the catalogue of programme types, purposes and classification rules is the Bursary's */
    private static final String FINANCE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_admin','OFFICE_super')";
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
                   String session, String entry, String channel, String q, String granularity,
                   String ptype, String purpose, String module, String office, Integer semester) {
        Filters(LocalDate from, LocalDate to, String types, String sex, String fac, String dept, String prog, Integer level,
                String session, String entry, String channel, String q, String granularity) {
            this(from, to, types, sex, fac, dept, prog, level, session, entry, channel, q, granularity, null, null, null, null, null);
        }

        /** V409: the same filters for another window or session */
        Filters with(LocalDate from, LocalDate to, String session) {
            return new Filters(from, to, types, sex, fac, dept, prog, level, session, entry, channel, q, granularity, ptype, purpose, module, office, semester);
        }
    }

    private static String code(String v) {
        return v == null || !v.trim().toUpperCase().matches("[A-Z][A-Z0-9_]{1,39}") ? null : v.trim().toUpperCase();
    }

    /** V409: the classification filters on top of the others */
    private static Filters classified(Filters f, String ptype, String purpose, String module, String office, Integer semester) {
        String off = office == null || !office.trim().matches("[A-Za-z]{2,30}") ? null : office.trim().toLowerCase();
        return new Filters(f.from(), f.to(), f.types(), f.sex(), f.fac(), f.dept(), f.prog(), f.level(), f.session(), f.entry(), f.channel(), f.q(), f.granularity(),
                code(ptype), code(purpose), code(module), off, semester != null && semester >= 1 && semester <= 3 ? semester : null);
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
            SELECT v.*, coalesce(c.label, v.category_code) AS category, coalesce(c.revenue, true) AS revenue,
                   coalesce(pt.label, v.programme_type) AS programme_type_label, coalesce(pu.label, v.purpose_code) AS purpose_label, pu.entitlement,
                   coalesce(ro.label, v.responsible_office) AS responsible_office_label
              FROM reporting.payments v LEFT JOIN finance.payment_category c ON c.code = v.category_code
              LEFT JOIN finance.programme_type pt ON pt.code = v.programme_type
              LEFT JOIN finance.payment_purpose pu ON pu.code = v.purpose_code
              LEFT JOIN ref.office ro ON ro.code = v.responsible_office
             WHERE (:pg::boolean IS NULL OR v.is_pg = :pg)
               AND (:bo::text IS NULL OR v.responsible_office = :bo)
               AND (:ptype::text IS NULL OR v.programme_type = :ptype)
               AND (:purpose::text IS NULL OR v.purpose_code = :purpose)
               AND (:module::text IS NULL OR v.source_module = :module)
               AND (:office::text IS NULL OR v.responsible_office = :office)
               AND (:semester::int IS NULL OR v.semester = :semester)
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
                .param("from", from, Types.DATE).param("to", to, Types.DATE)
                .param("bo", owner(), Types.VARCHAR).param("ptype", f.ptype(), Types.VARCHAR).param("purpose", f.purpose(), Types.VARCHAR)
                .param("module", f.module(), Types.VARCHAR).param("office", f.office(), Types.VARCHAR).param("semester", f.semester(), Types.INTEGER);
    }

    /** V409: the office that owns a purpose is held to the payments it owns, whatever the request says */
    private String owner() {
        String office = scope.office();
        return OWNERS.contains(office) ? office : null;
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
                                @RequestParam(required = false) String granularity, @RequestParam(defaultValue = "true") boolean compare,
                                @RequestParam(required = false) String ptype, @RequestParam(required = false) String purpose,
                                @RequestParam(required = false) String module, @RequestParam(required = false) String office,
                                @RequestParam(required = false) Integer semester) {
        Bound b = scope.bound();
        Filters f = classified(filters(from, to, types, sex, fac, dept, prog, level, session, entry, channel, q, granularity), ptype, purpose, module, office, semester);
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
        m.put("money", b.money() || owner() != null);
        m.put("transactions", scope.transactions() || owner() != null);
        m.put("office", scope.office());
        m.put("owner", owner() == null ? "" : owner());
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
        m.put("ptype", f.ptype() == null ? "" : f.ptype());
        m.put("purpose", f.purpose() == null ? "" : f.purpose());
        m.put("module", f.module() == null ? "" : f.module());
        m.put("office", f.office() == null ? "" : f.office());
        m.put("semester", f.semester() == null ? "" : String.valueOf(f.semester()));
        return m;
    }

    /** a breakdown of the summary: the key it is answered under and the codes it is grouped by (none for the totals) */
    private record Breakdown(String key, List<String> cols) {
    }

    private static final List<Breakdown> BREAKDOWNS = List.of(
            new Breakdown("totals", List.of()),
            new Breakdown("byCategory", List.of("category_code")),
            new Breakdown("byFaculty", List.of("faculty_code")),
            new Breakdown("byDepartment", List.of("faculty_code", "dept_code")),
            new Breakdown("byProgramme", List.of("faculty_code", "dept_code", "programme_code")),
            new Breakdown("byLevel", List.of("level")),
            new Breakdown("byGender", List.of("sex")),
            new Breakdown("byEntry", List.of("entry_mode")),
            new Breakdown("bySession", List.of("session")),
            new Breakdown("byChannel", List.of("channel")),
            new Breakdown("trend", List.of("bucket")),
            new Breakdown("byProgrammeType", List.of("programme_type")),
            new Breakdown("byPurpose", List.of("purpose_code")),
            new Breakdown("byTypeAndPurpose", List.of("programme_type", "purpose_code")),
            new Breakdown("bySourceModule", List.of("source_module")),
            new Breakdown("byResponsibleOffice", List.of("responsible_office")));

    /** the codes a breakdown may be grouped by, with the type a breakdown that does not group by one answers NULL as */
    private static final List<String[]> CODES = List.of(
            new String[] {"category_code", "text"}, new String[] {"faculty_code", "text"}, new String[] {"dept_code", "text"},
            new String[] {"programme_code", "text"}, new String[] {"level", "int"}, new String[] {"sex", "text"}, new String[] {"entry_mode", "text"},
            new String[] {"session", "text"}, new String[] {"channel", "text"}, new String[] {"bucket", "date"}, new String[] {"programme_type", "text"},
            new String[] {"purpose_code", "text"}, new String[] {"source_module", "text"}, new String[] {"responsible_office", "text"});

    /**
     * Oct 2026: every breakdown of the summary in one statement over one narrow read of the revenue rows — the codes, the
     * payer and the amount, the names joined only to the few rows each breakdown answers — each grouped twice by hashing
     * (by its codes and the payer, then by its codes), so the unique payers come without a DISTINCT that sorted every
     * row once per breakdown. On a live-shaped ledger the old statement re-sorted the full-width rows sixteen times and
     * spilled hundreds of megabytes to disk.
     */
    private static String ledgerSql() {
        String codes = String.join(", ", CODES.stream().filter(d -> !d[0].equals("bucket")).map(d -> "q." + d[0]).toList());
        StringBuilder sql = new StringBuilder("WITH r AS MATERIALIZED (\n    SELECT ").append(codes)
                .append(", date_trunc(:g, q.confirmed_at)::date AS bucket, q.payer_key, q.amount FROM (").append(ROWS).append(CONFIRMED).append(") q\n)\n");
        sql.append("SELECT y.*, coalesce(c.label, y.category_code) AS category, fa.name AS faculty, d.name AS department, pg.name AS programme,\n")
                .append("       coalesce(pt.label, y.programme_type) AS programme_type_label, coalesce(pu.label, y.purpose_code) AS purpose_label,\n")
                .append("       coalesce(ro.label, y.responsible_office) AS responsible_office_label\n  FROM (\n");
        for (int i = 0; i < BREAKDOWNS.size(); i++) {
            List<String> cols = BREAKDOWNS.get(i).cols();
            sql.append(i == 0 ? "" : "UNION ALL\n").append("SELECT ").append(i).append(" AS set_no");
            for (String[] d : CODES) {
                sql.append(", ").append(cols.contains(d[0]) ? "x." + d[0] : "NULL::" + d[1] + " AS " + d[0]);
            }
            String by = String.join(", ", cols);
            sql.append(", coalesce(sum(x.n), 0)::bigint AS transactions, count(x.payer_key)::bigint AS payers, coalesce(sum(x.amt), 0) AS amount\n")
                    .append("  FROM (SELECT ").append(cols.isEmpty() ? "" : by + ", ").append("r.payer_key, count(*) AS n, sum(r.amount) AS amt FROM r GROUP BY ")
                    .append(cols.isEmpty() ? "" : by + ", ").append("r.payer_key) x\n");
            if (!cols.isEmpty()) sql.append(" GROUP BY ").append(String.join(", ", cols.stream().map(c -> "x." + c).toList())).append("\n");
        }
        sql.append(") y\n")
                .append("  LEFT JOIN finance.payment_category c ON c.code = y.category_code\n")
                .append("  LEFT JOIN ref.faculty fa ON fa.code = y.faculty_code\n")
                .append("  LEFT JOIN ref.department d ON d.code = y.dept_code\n")
                .append("  LEFT JOIN ref.programme pg ON pg.code = y.programme_code\n")
                .append("  LEFT JOIN finance.programme_type pt ON pt.code = y.programme_type\n")
                .append("  LEFT JOIN finance.payment_purpose pu ON pu.code = y.purpose_code\n")
                .append("  LEFT JOIN ref.office ro ON ro.code = y.responsible_office\n")
                .append(" ORDER BY y.set_no, y.amount DESC, category, faculty, department, programme, y.level, y.sex, y.entry_mode, y.session, y.channel, y.bucket");
        return sql.toString();
    }

    private static final String LEDGER = ledgerSql();

    /** the totals and every breakdown — one statement, one read of the revenue rows */
    private void groups(Map<String, Object> out, Bound b, Filters f) {
        List<Map<String, Object>> rows = bind(jdbc.sql(LEDGER), b, f, f.from(), f.to()).param("g", f.granularity()).query().listOfRows();
        Map<String, List<Map<String, Object>>> lists = new LinkedHashMap<>();
        for (Breakdown bd : BREAKDOWNS) if (!bd.cols().isEmpty()) lists.put(bd.key(), new ArrayList<>());
        Map<String, Object> totals = null;
        for (Map<String, Object> g : rows) {
            Breakdown bd = BREAKDOWNS.get(((Number) g.get("set_no")).intValue());
            Map<String, Object> m = figures(g);
            switch (bd.key()) {
                case "totals" -> { totals = m; continue; }
                case "trend" -> m.put("bucket", String.valueOf(g.get("bucket")));
                case "byCategory" -> { m.put("code", g.get("category_code")); m.put("label", g.get("category")); }
                case "byFaculty" -> put(m, g, "faculty_code", "faculty");
                case "byDepartment" -> put(m, g, "faculty_code", "faculty", "dept_code", "department");
                case "byProgramme" -> put(m, g, "faculty_code", "faculty", "dept_code", "department", "programme_code", "programme");
                case "byProgrammeType" -> put(m, g, "programme_type", "programme_type_label");
                case "byPurpose" -> put(m, g, "purpose_code", "purpose_label");
                case "byTypeAndPurpose" -> put(m, g, "programme_type", "programme_type_label", "purpose_code", "purpose_label");
                case "byResponsibleOffice" -> put(m, g, "responsible_office", "responsible_office_label");
                default -> { for (String c : bd.cols()) m.put(c, g.get(c)); }
            }
            lists.get(bd.key()).add(m);
        }
        if (totals == null) totals = figures(Map.of("transactions", 0L, "payers", 0L, "amount", BigDecimal.ZERO));
        lists.get("trend").sort((x, y) -> String.valueOf(x.get("bucket")).compareTo(String.valueOf(y.get("bucket"))));
        lists.get("bySession").sort((x, y) -> String.valueOf(y.get("session")).compareTo(String.valueOf(x.get("session"))));
        lists.get("byLevel").sort((x, y) -> Integer.compare(x.get("level") == null ? 0 : ((Number) x.get("level")).intValue(), y.get("level") == null ? 0 : ((Number) y.get("level")).intValue()));
        out.put("totals", totals);
        for (Map.Entry<String, List<Map<String, Object>>> e : lists.entrySet()) out.put(e.getKey(), e.getValue());
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

    /**
     * The figures no revenue sum shows: pending references, failed gateway attempts, refunds paid. A pending reference is
     * read where it is (unconfirmed, unexpired, generated in the window — the ledger is restricted before it is read).
     * Failed attempts and refunds are found first, in the window, and only the payments they name are read from the
     * ledger (by reference, which the view restricts in each of its sources) — never the whole ledger to find a handful.
     */
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
        String[] failedRefs = jdbc.sql("""
                SELECT DISTINCT e.reference FROM finance.gateway_event e
                 WHERE e.outcome = ANY (string_to_array(:failed, ',')) AND e.reference IS NOT NULL
                   AND (:from::date IS NULL OR e.received_at >= :from::date) AND (:to::date IS NULL OR e.received_at < (:to::date + 1))
                """).param("failed", String.join(",", FAILED)).param("from", f.from(), Types.DATE).param("to", f.to(), Types.DATE)
                .query(String.class).list().toArray(String[]::new);
        long failed = 0;
        if (failedRefs.length > 0) {
            failed = ((Number) bind(jdbc.sql("""
                    WITH r AS (""" + ROWS + """
                     AND v.reference = ANY (:refs)
                    ) SELECT count(*) AS n FROM finance.gateway_event e JOIN r v ON v.reference = e.reference
                       WHERE e.outcome = ANY (string_to_array(:failed, ','))
                         AND (:from::date IS NULL OR e.received_at >= :from::date) AND (:to::date IS NULL OR e.received_at < (:to::date + 1))
                    """), b, f, f.from(), f.to()).param("refs", failedRefs).param("failed", String.join(",", FAILED)).query().singleRow().get("n")).longValue();
        }
        t.put("failed_count", failed);
        String[] refundRefs = jdbc.sql("""
                SELECT DISTINCT rf.reference FROM finance.refund rf
                 WHERE rf.state = 'PAID' AND rf.reference IS NOT NULL
                   AND (:from::date IS NULL OR rf.paid_at >= :from::date) AND (:to::date IS NULL OR rf.paid_at < (:to::date + 1))
                """).param("from", f.from(), Types.DATE).param("to", f.to(), Types.DATE).query(String.class).list().toArray(String[]::new);
        long refunded = 0;
        BigDecimal refundedAmount = BigDecimal.ZERO;
        if (refundRefs.length > 0) {
            Map<String, Object> refunds = bind(jdbc.sql("""
                    WITH r AS (""" + ROWS + """
                     AND v.reference = ANY (:refs)
                    ) SELECT count(*) AS n, coalesce(sum(rf.amount), 0) AS amount FROM finance.refund rf JOIN r v ON v.reference = rf.reference
                       WHERE rf.state = 'PAID'
                         AND (:from::date IS NULL OR rf.paid_at >= :from::date) AND (:to::date IS NULL OR rf.paid_at < (:to::date + 1))
                    """), b, f, f.from(), f.to()).param("refs", refundRefs).query().singleRow();
            refunded = ((Number) refunds.get("n")).longValue();
            refundedAmount = (BigDecimal) refunds.get("amount");
        }
        t.put("refunded_count", refunded);
        t.put("refunded_amount", refundedAmount);
        t.put("net_revenue", ((BigDecimal) t.get("revenue")).subtract(refundedAmount));
        return t;
    }

    /** the period before: the same length of days before the window, or the session before the session asked for */
    private Map<String, Object> comparison(Bound b, Filters f) {
        LocalDate from = f.from(), to = f.to();
        Filters prev;
        String label;
        if (from != null && to != null) {
            long days = java.time.temporal.ChronoUnit.DAYS.between(from, to) + 1;
            prev = f.with(from.minusDays(days), from.minusDays(1), f.session());
            label = "Previous " + days + " day" + (days == 1 ? "" : "s");
        } else if (f.session() != null) {
            int y = Integer.parseInt(f.session().substring(0, 4)) - 1;
            String before = y + "/" + (y + 1);
            prev = f.with(null, null, before);
            label = "Session " + before;
        } else {
            return null;
        }
        Map<String, Object> row = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + CONFIRMED + """
                ) SELECT coalesce(sum(x.n), 0)::bigint AS transactions, count(*) AS payers, coalesce(sum(x.amt), 0) AS amount
                    FROM (SELECT payer_key, count(*) AS n, sum(amount) AS amt FROM r GROUP BY payer_key) x
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
        // V409: the classification dimensions
        o.put("programmeTypes", jdbc.sql("SELECT code, label FROM finance.programme_type WHERE active ORDER BY ord, code").query().listOfRows());
        o.put("purposes", jdbc.sql("SELECT code, label FROM finance.payment_purpose WHERE active ORDER BY ord, code").query().listOfRows());
        o.put("sourceModules", jdbc.sql("SELECT DISTINCT source_module FROM finance.payment_classification ORDER BY source_module").query(String.class).list());
        o.put("offices", jdbc.sql("""
                SELECT DISTINCT c.responsible_office AS code, o.label FROM finance.payment_classification c JOIN ref.office o ON o.code = c.responsible_office ORDER BY o.label
                """).query().listOfRows());
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
                                     @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size,
                                     @RequestParam(required = false) String ptype, @RequestParam(required = false) String purpose,
                                     @RequestParam(required = false) String module, @RequestParam(required = false) String office,
                                     @RequestParam(required = false) Integer semester) {
        Bound b = scope.bound();
        Filters f = classified(filters(from, to, types, sex, fac, dept, prog, level, session, entry, channel, q, null), ptype, purpose, module, office, semester);
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
                       r.session, r.category_code, r.category, r.purpose, r.kind, r.amount, r.confirmed_at, r.generated_at, r.channel, r.status,
                       r.programme_type, r.programme_type_label, r.admission_route, r.study_mode, r.purpose_code, r.purpose_label, r.entitlement,
                       r.source_module, r.responsible_office, r.responsible_office_label, r.semester, r.jamb_reg_no, r.application_no, r.exam_no,
                       (SELECT e.gateway_ref FROM finance.gateway_event e WHERE e.reference = r.reference AND e.outcome IN ('SETTLED', 'ALREADY_SETTLED') AND e.gateway_ref IS NOT NULL
                         ORDER BY e.received_at DESC LIMIT 1) AS gateway_reference,
                       (SELECT coalesce(sum(rf.amount), 0) FROM finance.refund rf WHERE rf.state = 'PAID' AND (rf.reference = r.reference OR rf.source_reference = r.reference)) AS refunded
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
            // V409: the ledger's word for it — paid, refunded in part or in whole
            BigDecimal refunded = r.get("refunded") instanceof BigDecimal d ? d : BigDecimal.ZERO;
            BigDecimal amount = r.get("amount") instanceof BigDecimal d ? d : BigDecimal.ZERO;
            x.put("ledger_status", refunded.signum() == 0 ? "PAID" : refunded.compareTo(amount) >= 0 ? "REFUNDED" : "PART_REFUNDED");
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

    /** V409: purpose — the purpose a payment of the category is for (finance.payment_purpose); left out, it stays as it was */
    public record CategoryIn(@NotBlank @Size(max = 120) String label, List<String> kinds, @Size(max = 400) String pattern, Integer ord, Boolean revenue, Boolean active,
                             @Size(max = 40) String purpose) {
    }

    @GetMapping("/finance/categories")
    @PreAuthorize(SUMMARY_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> categories() {
        return jdbc.sql("SELECT code, label, kinds, pattern, ord, revenue, active, updated_at, purpose FROM finance.payment_category ORDER BY ord, code").query().listOfRows()
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
        String purpose = body.purpose() == null || body.purpose().isBlank() ? null : code(body.purpose());
        if (body.purpose() != null && !body.purpose().isBlank()
                && (purpose == null || !jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.payment_purpose WHERE code = :p)").param("p", purpose).query(Boolean.class).single())) {
            throw new DomainRuleViolation("PAY_CATEGORY_PURPOSE", "That purpose is not on the catalogue.", new DomainRuleViolation.Remedy("Choose a purpose from the list, or state it first.", "Bursary"));
        }
        try {
            Map<String, Object> out = jdbc.sql("SELECT code, label, kinds, pattern, ord, revenue, active, updated_at FROM finance.set_payment_category(:c, :l, :k::text[], :p, :o, :r, :a)")
                    .param("c", c).param("l", body.label().trim()).param("k", kinds).param("p", body.pattern(), Types.VARCHAR)
                    .param("o", body.ord(), Types.INTEGER).param("r", body.revenue(), Types.BOOLEAN).param("a", body.active(), Types.BOOLEAN)
                    .query().singleRow().entrySet().stream().collect(LinkedHashMap::new, (m, e) -> m.put(e.getKey(), "kinds".equals(e.getKey()) ? kinds(e.getValue()) : e.getValue()), Map::putAll);
            if (purpose != null) jdbc.sql("UPDATE finance.payment_category SET purpose = :p WHERE code = :c").param("p", purpose).param("c", c).update();
            out.put("purpose", jdbc.sql("SELECT purpose FROM finance.payment_category WHERE code = :c").param("c", c).query(String.class).single());
            return out;
        } catch (org.springframework.dao.DataAccessException e) {
            throw new DomainRuleViolation("PAY_CATEGORY_PATTERN", "The purpose pattern is not a regular expression the database accepts.",
                    new DomainRuleViolation.Remedy("Try a plain prefix such as ^gst", "Bursary"));
        }
    }

    /* ── V409: the classification catalogue — programme types, purposes and the rules that name a payment's module and office ── */

    @GetMapping("/finance/classification")
    @PreAuthorize(SUMMARY_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> classification() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("programmeTypes", jdbc.sql("SELECT code, label, ord, active, entry_modes, programme_categories, study_mode, description, updated_at FROM finance.programme_type ORDER BY ord, code")
                .query().listOfRows().stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.put("entry_modes", kinds(r.get("entry_modes"))); m.put("programme_categories", kinds(r.get("programme_categories"))); return m; }).toList());
        out.put("purposes", jdbc.sql("SELECT code, label, ord, active, gl_account, entitlement, updated_at FROM finance.payment_purpose ORDER BY ord, code").query().listOfRows());
        out.put("rules", jdbc.sql("""
                SELECT c.id, c.purpose, pu.label AS purpose_label, c.programme_type, pt.label AS programme_type_label, c.source_module, c.responsible_office,
                       o.label AS responsible_office_label, c.note, c.updated_at
                  FROM finance.payment_classification c
                  LEFT JOIN finance.payment_purpose pu ON pu.code = c.purpose
                  LEFT JOIN finance.programme_type pt ON pt.code = c.programme_type
                  LEFT JOIN ref.office o ON o.code = c.responsible_office
                 ORDER BY c.purpose NULLS FIRST, c.programme_type NULLS FIRST
                """).query().listOfRows());
        out.put("categories", jdbc.sql("SELECT code, label, purpose FROM finance.payment_category ORDER BY ord, code").query().listOfRows());
        out.put("offices", jdbc.sql("SELECT code, label FROM ref.office WHERE code NOT IN ('student', 'applicant', 'putmecbt', 'extexaminer') ORDER BY label").query().listOfRows());
        out.put("entryModes", List.of("UTME", "DIRECT_ENTRY", "TRANSFER", "POSTGRADUATE", "JUPEB", "SANDWICH", "CCE"));
        out.put("programmeCategories", jdbc.sql("SELECT DISTINCT category FROM ref.programme WHERE category IS NOT NULL ORDER BY category").query(String.class).list());
        return out;
    }

    public record ProgrammeTypeIn(@NotBlank @Size(max = 80) String label, List<String> entryModes, List<String> programmeCategories, @Size(max = 20) String studyMode,
                                  Integer ord, Boolean active, @Size(max = 300) String description) {
    }

    /** a programme type stated or amended: its label and the entry modes and programme categories that are of it */
    @PutMapping("/finance/programme-types/{code}")
    @PreAuthorize(FINANCE_SETTERS)
    @Transactional
    Map<String, Object> setProgrammeType(@PathVariable String code, @Valid @RequestBody ProgrammeTypeIn body) {
        String c = code(code);
        if (c == null) {
            throw new DomainRuleViolation("PAY_TYPE_CODE", "A programme type code is capital letters and underscores, up to thirty characters.",
                    new DomainRuleViolation.Remedy("For example SANDWICH or PRELIMINARY.", "Bursary"));
        }
        AuditContextHolder.required();
        String mode = body.studyMode() == null || body.studyMode().isBlank() ? null : body.studyMode().trim().toUpperCase();
        if (mode != null && !Set.of("FULL_TIME", "PART_TIME", "SANDWICH").contains(mode)) {
            throw new DomainRuleViolation("PAY_TYPE_MODE", "A study mode is full-time, part-time or sandwich.", new DomainRuleViolation.Remedy("Choose one, or leave it blank.", "Bursary"));
        }
        Map<String, Object> r = jdbc.sql("SELECT code, label, ord, active, entry_modes, programme_categories, study_mode, description, updated_at FROM finance.set_programme_type(:c, :l, :e::text[], :p::text[], :m, :o, :a, :d)")
                .param("c", c).param("l", body.label().trim())
                .param("e", body.entryModes() == null ? new String[0] : body.entryModes().toArray(String[]::new))
                .param("p", body.programmeCategories() == null ? new String[0] : body.programmeCategories().toArray(String[]::new))
                .param("m", mode, Types.VARCHAR).param("o", body.ord(), Types.INTEGER).param("a", body.active(), Types.BOOLEAN).param("d", body.description(), Types.VARCHAR)
                .query().singleRow();
        Map<String, Object> m = new LinkedHashMap<>(r);
        m.put("entry_modes", kinds(r.get("entry_modes")));
        m.put("programme_categories", kinds(r.get("programme_categories")));
        return m;
    }

    public record PurposeIn(@NotBlank @Size(max = 80) String label, Integer ord, Boolean active, @Size(max = 10) String glAccount, @Size(max = 300) String entitlement) {
    }

    /** a purpose stated or amended: its label, the income account it posts to and what it entitles */
    @PutMapping("/finance/purposes/{code}")
    @PreAuthorize(FINANCE_SETTERS)
    @Transactional
    Map<String, Object> setPurpose(@PathVariable String code, @Valid @RequestBody PurposeIn body) {
        String c = code(code);
        if (c == null) {
            throw new DomainRuleViolation("PAY_PURPOSE_CODE", "A purpose code is capital letters and underscores, up to forty characters.",
                    new DomainRuleViolation.Remedy("For example CONVOCATION_FEE.", "Bursary"));
        }
        if ("OTHER".equals(c) && Boolean.FALSE.equals(body.active())) {
            throw new DomainRuleViolation("PAY_PURPOSE_OTHER", "The purpose Other stays, so every payment has one.", new DomainRuleViolation.Remedy("Rename it instead.", "Bursary"));
        }
        String account = body.glAccount() == null || body.glAccount().isBlank() ? "4090" : body.glAccount().trim();
        if (!jdbc.sql("SELECT EXISTS (SELECT 1 FROM finance.gl_account WHERE code = :a AND code LIKE '4%')").param("a", account).query(Boolean.class).single()) {
            throw new DomainRuleViolation("PAY_PURPOSE_ACCOUNT", "Account " + account + " is not an income account of the general ledger.",
                    new DomainRuleViolation.Remedy("Choose an income account (4010–4090) from the chart of accounts.", "Bursary"));
        }
        java.util.UUID by = AuditContextHolder.required().actorId();
        return jdbc.sql("""
                INSERT INTO finance.payment_purpose (code, label, ord, active, gl_account, entitlement, updated_by, updated_at)
                VALUES (:c, :l, coalesce(:o, 100), coalesce(:a, true), :g, nullif(btrim(coalesce(:e, '')), ''), :by, now())
                ON CONFLICT (code) DO UPDATE SET label = EXCLUDED.label, ord = coalesce(:o, finance.payment_purpose.ord), active = EXCLUDED.active,
                       gl_account = EXCLUDED.gl_account, entitlement = EXCLUDED.entitlement, updated_by = EXCLUDED.updated_by, updated_at = now()
                RETURNING code, label, ord, active, gl_account, entitlement, updated_at
                """).param("c", c).param("l", body.label().trim()).param("o", body.ord(), Types.INTEGER).param("a", body.active(), Types.BOOLEAN)
                .param("g", account).param("e", body.entitlement(), Types.VARCHAR).param("by", by).query().singleRow();
    }

    public record RuleIn(@Size(max = 40) String purpose, @Size(max = 30) String programmeType, @NotBlank @Size(max = 30) String sourceModule,
                         @NotBlank @Size(max = 30) String responsibleOffice, @Size(max = 300) String note) {
    }

    /** a classification rule stated or amended: for a purpose, a programme type, both or neither, the source module and the office that owns it */
    @PutMapping("/finance/classification")
    @PreAuthorize(FINANCE_SETTERS)
    @Transactional
    Map<String, Object> setRule(@Valid @RequestBody RuleIn body) {
        AuditContextHolder.required();
        String purpose = body.purpose() == null || body.purpose().isBlank() ? null : code(body.purpose());
        String type = body.programmeType() == null || body.programmeType().isBlank() ? null : code(body.programmeType());
        String module = code(body.sourceModule());
        if ((body.purpose() != null && !body.purpose().isBlank() && purpose == null) || (body.programmeType() != null && !body.programmeType().isBlank() && type == null) || module == null) {
            throw new DomainRuleViolation("PAY_RULE_CODE", "Purposes, programme types and source modules are written in capitals and underscores.",
                    new DomainRuleViolation.Remedy("Choose them from the lists.", "Bursary"));
        }
        try {
            return jdbc.sql("SELECT id, purpose, programme_type, source_module, responsible_office, note, updated_at FROM finance.set_payment_classification(:p, :t, :m, :o, :n)")
                    .param("p", purpose, Types.VARCHAR).param("t", type, Types.VARCHAR).param("m", module).param("o", body.responsibleOffice().trim().toLowerCase())
                    .param("n", body.note(), Types.VARCHAR).query().singleRow();
        } catch (org.springframework.dao.DataIntegrityViolationException e) {
            throw new DomainRuleViolation("PAY_RULE_UNKNOWN", "That purpose, programme type or office is not on the catalogue.",
                    new DomainRuleViolation.Remedy("State the purpose or programme type first, and choose the office from the register.", "Bursary"));
        }
    }
}
