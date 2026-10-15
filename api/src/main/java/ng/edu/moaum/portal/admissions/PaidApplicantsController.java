package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The Post-UTME paid applicants report (V479): the candidates of an admission session whose Post-UTME application fee the
 * payment service has confirmed — one row an application, from admissions.post_utme_paid_applicants, which holds the rules
 * once — filtered on the server, the figures above it counted from the same rows, and the whole filtered set handed to the
 * portal's Excel and PDF engine, each download recorded on the audit spine (admissions.report_export).
 *
 * <p>Read and exported by the Academic Office, the Registry, the Directorate of ICT and the platform, university-wide; and
 * by a Dean or Faculty Officer within the faculty, a Head of Department within the department — the scope the server holds
 * (OfficeScope.bound), whatever the request names. The portal's permissions are offices: PAID_VIEWERS stands for
 * VIEW_PAID_POST_UTME_APPLICANTS, PAID_EXPORTERS for EXPORT_PAID_POST_UTME_APPLICANTS_EXCEL and _PDF.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}/paid-applicants")
class PaidApplicantsController {

    static final String PAID_VIEWERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod')";
    static final String PAID_EXPORTERS = PAID_VIEWERS;
    static final String REPORT = "POST_UTME_PAID_APPLICANTS";
    private static final Set<String> STATUSES = Set.of("VERIFIED", "PENDING", "REVERSED", "NOT_STARTED", "ALL");

    /** the filters, every one a bound parameter; payment dates are Lagos days */
    private static final String WHERE = """
             WHERE (CAST(:status AS text) IS NULL OR r.payment_status = CAST(:status AS text))
               AND (CAST(:fac AS text) IS NULL OR r.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR r.dept_code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR r.programme_code = CAST(:prog AS text))
               AND (CAST(:sex AS text) IS NULL OR r.sex = CAST(:sex AS text))
               AND (CAST(:entry AS text) IS NULL OR r.entry_mode = CAST(:entry AS text))
               AND (CAST(:from AS date) IS NULL OR r.paid_at >= (CAST(:from AS date)::timestamp AT TIME ZONE 'Africa/Lagos'))
               AND (CAST(:to AS date) IS NULL OR r.paid_at < ((CAST(:to AS date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos'))
               AND (CAST(:jamb AS text) IS NULL OR upper(r.jamb_reg_no) = upper(CAST(:jamb AS text)))
               AND (CAST(:q AS text) IS NULL
                    OR lower(concat_ws(' ', r.full_name, r.other_names, r.surname, r.jamb_reg_no, r.application_no, r.programme)) LIKE CAST(:q AS text))
            """;
    private static final String COLUMNS = """
            r.application_id, r.application_no, r.jamb_reg_no, r.full_name, r.programme, r.programme_code, r.faculty_code, r.faculty,
            r.dept_code, r.department, r.sex, r.entry_mode, r.utme_aggregate, r.phone, r.email, r.payment_status, r.paid_at,
            r.payment_reference, r.receipt_no, r.channel, r.amount, r.verified_payments, r.missing
            """;
    /** what the downloaded report carries: its eight columns and what each row is missing */
    private static final String EXPORT_COLUMNS = """
            r.jamb_reg_no, r.full_name, r.programme, r.faculty, r.department, r.sex, r.entry_mode, r.utme_aggregate, r.phone, r.email,
            r.payment_status, r.missing
            """;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    PaidApplicantsController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the filters as the report reads them — the faculty, department and programme already held to the office's scope;
     *  {@code search} as typed, for the record and the page, and its LIKE pattern for the query */
    record Filters(String status, String fac, String dept, String prog, String sex, String entry, LocalDate from, LocalDate to, String jamb, String search) {
        String like() {
            return search == null ? null : "%" + search.toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        }

        Filters anyStatus() {
            return new Filters(null, fac, dept, prog, sex, entry, from, to, jamb, search);
        }

        Filters anySex() {
            return new Filters(status, fac, dept, prog, null, entry, from, to, jamb, search);
        }

        Filters anyEntry() {
            return new Filters(status, fac, dept, prog, sex, null, from, to, jamb, search);
        }

        Map<String, Object> words() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("status", status == null ? "ALL" : status);
            if (fac != null) m.put("faculty", fac);
            if (dept != null) m.put("department", dept);
            if (prog != null) m.put("programme", prog);
            if (sex != null) m.put("gender", sex);
            if (entry != null) m.put("entryMode", entry);
            if (from != null) m.put("paidFrom", from.toString());
            if (to != null) m.put("paidTo", to.toString());
            if (jamb != null) m.put("jamb", jamb);
            if (search != null) m.put("search", search);
            return m;
        }
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String session(String session, String year) {
        String s = session + "/" + year;
        if (!s.matches("\\d{4}/\\d{4}")) throw new DomainRuleViolation("ADM_SESSION", "An admission session is named YYYY/YYYY.",
                new DomainRuleViolation.Remedy("Choose the admission session.", "Academic Office"));
        return s;
    }

    private Filters filters(String status, String fac, String dept, String prog, String sex, String entry, LocalDate from, LocalDate to, String jamb, String q) {
        OfficeScope.Bound b = scope.bound(blank(fac), blank(dept), blank(prog));
        String st = blank(status) == null ? "VERIFIED" : status.trim().toUpperCase();
        if (!STATUSES.contains(st)) throw new DomainRuleViolation("PAID_STATUS", "'" + status + "' is not a payment status of this report.",
                new DomainRuleViolation.Remedy("Choose Verified, Pending, Reversed, Not started or All.", "You"));
        String sx = blank(sex) == null ? null : sex.trim().toUpperCase();
        if (sx != null && !Set.of("M", "F").contains(sx)) throw new DomainRuleViolation("PAID_GENDER", "Gender is M or F.",
                new DomainRuleViolation.Remedy("Choose Male or Female, or leave it for both.", "You"));
        String en = blank(entry) == null ? null : entry.trim().toUpperCase();
        if (en != null && !Set.of("UTME", "DIRECT_ENTRY", "TRANSFER").contains(en)) throw new DomainRuleViolation("PAID_ENTRY", "'" + entry + "' is not a Post-UTME entry mode.",
                new DomainRuleViolation.Remedy("Choose UTME, Direct Entry or Transfer, or leave it for all.", "You"));
        if (from != null && to != null && to.isBefore(from)) throw new DomainRuleViolation("PAID_DATES", "The payment date range ends before it begins.",
                new DomainRuleViolation.Remedy("Set the From date on or before the To date.", "You"));
        String search = blank(q);
        if (search != null && search.length() > 80) search = search.substring(0, 80);
        return new Filters("ALL".equals(st) ? null : st, b.fac(), b.dept(), b.prog(), sx, en, from, to, blank(jamb), search);
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, String s, Filters f) {
        return spec.param("s", s).param("status", f.status(), Types.VARCHAR).param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR)
                .param("prog", f.prog(), Types.VARCHAR).param("sex", f.sex(), Types.VARCHAR).param("entry", f.entry(), Types.VARCHAR)
                .param("from", f.from(), Types.DATE).param("to", f.to(), Types.DATE).param("jamb", f.jamb(), Types.VARCHAR).param("q", f.like(), Types.VARCHAR);
    }

    /** a text[] column as a list, for JSON */
    private static void lists(List<Map<String, Object>> rows, String col) {
        for (Map<String, Object> r : rows) {
            Object v = r.get(col);
            if (v instanceof java.sql.Array a) {
                try {
                    r.put(col, List.of((Object[]) a.getArray()));
                } catch (java.sql.SQLException e) {
                    throw new IllegalStateException(e);
                }
            }
        }
    }

    /** what the selected set is missing, field by field (a row is never left out for it) */
    private List<Map<String, Object>> missing(String s, Filters f) {
        return bind(jdbc.sql("SELECT m AS field, count(*) AS n FROM admissions.post_utme_paid_applicants(:s) r CROSS JOIN LATERAL unnest(r.missing) m"
                + WHERE + " GROUP BY m ORDER BY m"), s, f).query().listOfRows();
    }

    /** a page of the applicants the filters select, names A–Z, with what the selected set is missing */
    @GetMapping
    @PreAuthorize(PAID_VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@PathVariable String session, @PathVariable String year,
                             @RequestParam(required = false) String status, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String prog, @RequestParam(required = false) String sex, @RequestParam(required = false) String entry,
                             @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                             @RequestParam(required = false) String jamb, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String s = session(session, year);
        Filters f = filters(status, fac, dept, prog, sex, entry, from, to, jamb, q);
        int sz = Math.max(1, Math.min(size, 200)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql("SELECT count(*) OVER () AS total_rows, " + COLUMNS
                + " FROM admissions.post_utme_paid_applicants(:s) r" + WHERE + " ORDER BY r.full_name, r.application_id LIMIT :n OFFSET :o"), s, f)
                .param("n", sz).param("o", (long) pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        lists(rows, "missing");
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        out.put("missing", missing(s, f));
        return out;
    }

    /** the figures above the report, from the very rows the report reads: in all, by faculty and programme within the filters;
     *  by gender, entry mode and payment status with every other filter kept */
    @GetMapping("/summary")
    @PreAuthorize(PAID_VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@PathVariable String session, @PathVariable String year,
                                @RequestParam(required = false) String status, @RequestParam(required = false) String fac, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String prog, @RequestParam(required = false) String sex, @RequestParam(required = false) String entry,
                                @RequestParam(required = false) LocalDate from, @RequestParam(required = false) LocalDate to,
                                @RequestParam(required = false) String jamb, @RequestParam(required = false) String q) {
        String s = session(session, year);
        Filters f = filters(status, fac, dept, prog, sex, entry, from, to, jamb, q);
        List<Map<String, Object>> groups = bind(jdbc.sql("""
                SELECT grouping(r.faculty_code) AS g_fac, grouping(r.programme_code) AS g_prog,
                       r.faculty_code, r.faculty, r.programme_code, r.programme, count(*) AS n
                  FROM admissions.post_utme_paid_applicants(:s) r""" + WHERE + """
                 GROUP BY GROUPING SETS ((), (r.faculty_code, r.faculty), (r.faculty_code, r.faculty, r.programme_code, r.programme))
                """), s, f).query().listOfRows();
        long total = 0;
        List<Map<String, Object>> byFaculty = new ArrayList<>(), byProgramme = new ArrayList<>();
        for (Map<String, Object> g : groups) {
            long n = ((Number) g.get("n")).longValue();
            Map<String, Object> row = new LinkedHashMap<>();
            if (grouped(g, "g_prog")) {
                row.put("faculty_code", g.get("faculty_code"));
                row.put("faculty", g.get("faculty"));
                row.put("programme_code", g.get("programme_code"));
                row.put("programme", g.get("programme"));
                byProgramme.add(row);
            } else if (grouped(g, "g_fac")) {
                row.put("faculty_code", g.get("faculty_code"));
                row.put("faculty", g.get("faculty"));
                byFaculty.add(row);
            } else {
                total = n;
                continue;
            }
            row.put("n", n);
        }
        Comparator<Map<String, Object>> byN = (a, b) -> Long.compare(((Number) b.get("n")).longValue(), ((Number) a.get("n")).longValue());
        byFaculty.sort(byN);
        byProgramme.sort(byN);
        // gender and entry mode counted with every other filter kept and their own left out, so each figure stays a door
        List<Map<String, Object>> bySex = bind(jdbc.sql("SELECT r.sex, count(*) AS n FROM admissions.post_utme_paid_applicants(:s) r"
                + WHERE + " GROUP BY 1 ORDER BY 2 DESC"), s, f.anySex()).query().listOfRows();
        List<Map<String, Object>> byEntry = bind(jdbc.sql("SELECT r.entry_mode, count(*) AS n FROM admissions.post_utme_paid_applicants(:s) r"
                + WHERE + " GROUP BY 1 ORDER BY 2 DESC"), s, f.anyEntry()).query().listOfRows();
        List<Map<String, Object>> byStatus = bind(jdbc.sql("SELECT r.payment_status AS status, count(*) AS n FROM admissions.post_utme_paid_applicants(:s) r"
                + WHERE + " GROUP BY 1 ORDER BY 1"), s, f.anyStatus()).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("total", total);
        out.put("bySex", bySex);
        out.put("byEntryMode", byEntry);
        out.put("byFaculty", byFaculty);
        out.put("byProgramme", byProgramme);
        out.put("byStatus", byStatus);
        return out;
    }

    /** what the filter bar offers: the sessions with applications, and the faculties, departments and programmes the session's
     *  applicants applied for, within the office's scope */
    @GetMapping("/options")
    @PreAuthorize(PAID_VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> options(@PathVariable String session, @PathVariable String year) {
        String s = session(session, year);
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("sessions", jdbc.sql("SELECT DISTINCT a.session FROM admissions.application a ORDER BY 1 DESC").query(String.class).list());
        out.put("programmes", jdbc.sql("""
                SELECT r.faculty_code, r.faculty, r.dept_code, r.department, r.programme_code, r.programme, count(*) AS applicants
                  FROM admissions.post_utme_paid_applicants(:s) r
                 WHERE r.programme_code IS NOT NULL
                   AND (CAST(:fac AS text) IS NULL OR r.faculty_code = CAST(:fac AS text))
                   AND (CAST(:dept AS text) IS NULL OR r.dept_code = CAST(:dept AS text))
                 GROUP BY 1, 2, 3, 4, 5, 6
                 ORDER BY r.faculty, r.department, r.programme
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).query().listOfRows());
        out.put("scope", scopeMap());
        return out;
    }

    record ExportIn(@NotBlank @Pattern(regexp = "XLSX|PDF") String format, String status, String fac, String dept, String prog, String sex, String entry,
                    LocalDate from, LocalDate to, @Size(max = 40) String jamb, @Size(max = 80) String q) {
    }

    /** every applicant the filters select, names A–Z, for the Excel and PDF engine — and the download recorded on the audit
     *  spine: who, when, the session, the format, the filters and the number of rows */
    @PostMapping("/export")
    @PreAuthorize(PAID_EXPORTERS)
    @Transactional
    Map<String, Object> export(@PathVariable String session, @PathVariable String year, @Valid @RequestBody ExportIn body) {
        String s = session(session, year);
        Filters f = filters(body.status(), body.fac(), body.dept(), body.prog(), body.sex(), body.entry(), body.from(), body.to(), body.jamb(), body.q());
        List<Map<String, Object>> rows = bind(jdbc.sql("SELECT " + EXPORT_COLUMNS + " FROM admissions.post_utme_paid_applicants(:s) r" + WHERE
                + " ORDER BY r.full_name, r.application_id"), s, f).query().listOfRows();
        lists(rows, "missing");
        AuditContext ctx = AuditContextHolder.required();
        Map<String, Object> words = f.words();
        jdbc.sql("""
                INSERT INTO admissions.report_export (report, session, format, filters, row_count, exported_by, office)
                VALUES (:r, :s, :fmt,
                        jsonb_strip_nulls(jsonb_build_object('status', CAST(:status AS text), 'faculty', CAST(:fac AS text), 'department', CAST(:dept AS text),
                            'programme', CAST(:prog AS text), 'gender', CAST(:sex AS text), 'entryMode', CAST(:entry AS text),
                            'paidFrom', CAST(:from AS date), 'paidTo', CAST(:to AS date), 'jamb', CAST(:jamb AS text), 'search', CAST(:search AS text))),
                        :n, :by, (SELECT o.code FROM ref.office o WHERE o.code = CAST(:office AS text)))
                """).param("r", REPORT).param("s", s).param("fmt", body.format()).param("status", String.valueOf(words.get("status")))
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("sex", f.sex(), Types.VARCHAR).param("entry", f.entry(), Types.VARCHAR).param("from", f.from(), Types.DATE).param("to", f.to(), Types.DATE)
                .param("jamb", f.jamb(), Types.VARCHAR).param("search", f.search(), Types.VARCHAR).param("n", rows.size())
                .param("by", ctx.actorId()).param("office", ctx.actorOffice(), Types.VARCHAR).update();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("format", body.format());
        out.put("filters", words);
        out.put("labels", labels(f));
        out.put("scope", scopeMap());
        out.put("generatedBy", jdbc.sql("SELECT nullif(btrim(coalesce(surname, '') || ', ' || coalesce(given_names, '')), ',') FROM iam.person WHERE id = :p")
                .param("p", ctx.actorId()).query(String.class).optional().orElse(null));
        out.put("total", rows.size());
        out.put("rows", rows);
        return out;
    }

    /** the faculty, department and programme of the filters by name, for the heading of a download */
    private Map<String, Object> labels(Filters f) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (f.fac() != null) m.put("faculty", jdbc.sql("SELECT name FROM ref.faculty WHERE code = :c").param("c", f.fac()).query(String.class).optional().orElse(f.fac()));
        if (f.dept() != null) m.put("department", jdbc.sql("SELECT name FROM ref.department WHERE code = :c").param("c", f.dept()).query(String.class).optional().orElse(f.dept()));
        if (f.prog() != null) m.put("programme", jdbc.sql("SELECT name FROM ref.programme WHERE code = :c").param("c", f.prog()).query(String.class).optional().orElse(f.prog()));
        return m;
    }

    private static boolean grouped(Map<String, Object> g, String k) {
        return ((Number) g.get(k)).intValue() == 0;
    }

    private Map<String, Object> scopeMap() {
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("faculty", b.fac());
        m.put("department", b.dept());
        m.put("programme", b.prog());
        return m;
    }
}
