package ng.edu.moaum.portal.admissions;

import java.sql.Types;
import java.util.ArrayList;
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
 * The acceptance fee monitor (V724): every released Post-UTME offer of an admission session — UTME and Direct Entry, not
 * declined or lapsed — with the acceptance fee as stated now, what the bank has confirmed, the balance, the first amount paid
 * (the figure before a revision), any excess, the reference awaiting the bank and a band: NOT_PAID, PENDING, PART_PAID (owing a
 * balance after the fee was revised), SETTLED_IN_PARTS (the revised fee met in more than one payment), PAID_IN_FULL (met in one),
 * OVERPAID (more confirmed than the fee as stated now — the refund desk's), CONFIRMED_WITHOUT_REFERENCE (confirmed by hand or
 * carried from the old portal; owes nothing). One row an offer, from admissions.acceptance_fee_monitor, read once a request in
 * a materialised CTE and filtered in SQL; the figures
 * above the list counted from the same rows; the whole filtered set handed to the portal's Excel and PDF engine, each
 * download recorded on the audit spine (admissions.report_export).
 *
 * <p>Read by the paid-applicants report's viewers — the Academic Office, the Registry, the Directorate of ICT and the
 * platform university-wide; a Dean or Faculty Officer within the faculty, a Head of Department within the department, the
 * scope the server holds (OfficeScope.bound), whatever the request names — and by the Bursary, the Students Account Officer
 * and the audit directorate, whose money it is.
 */
@RestController
@RequestMapping("/api/v1/admissions/sessions/{session}/{year}/acceptance-fees")
class AcceptanceFeeMonitorController {

    static final String VIEWERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_super',"
            + "'OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_bursar','OFFICE_studentaccounts','OFFICE_audit','OFFICE_deputyaudit')";
    static final String REPORT = "ACCEPTANCE_FEE_MONITOR";
    /** the bands, in the order the tiles stand: owing first; then settled, more than settled, and confirmed with no reference behind it (V724) */
    static final List<String> BANDS = List.of("NOT_PAID", "PENDING", "PART_PAID", "SETTLED_IN_PARTS", "PAID_IN_FULL", "OVERPAID", "CONFIRMED_WITHOUT_REFERENCE");
    private static final Set<String> ENTRY_MODES = Set.of("UTME", "DIRECT_ENTRY");

    /** the monitor read once a request: its rows with the programme's department (a Head of Department's bound) and the faculty's name —
     *  materialised, so the monitor is evaluated exactly once however the statement reads it */
    private static final String ROWS = """
            WITH r AS MATERIALIZED (
                SELECT m.*, pr.dept_code, fa.name AS faculty
                  FROM admissions.acceptance_fee_monitor(:s) m
                  LEFT JOIN ref.programme pr ON pr.code = m.programme_code
                  LEFT JOIN ref.faculty fa ON fa.code = m.faculty_code)
            """;
    /** the filters, every one a bound parameter */
    private static final String WHERE = """
             WHERE (CAST(:band AS text) IS NULL OR r.band = CAST(:band AS text))
               AND (CAST(:fac AS text) IS NULL OR r.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR r.dept_code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR r.programme_code = CAST(:prog AS text))
               AND (CAST(:entry AS text) IS NULL OR r.entry_mode = CAST(:entry AS text))
               AND (CAST(:q AS text) IS NULL
                    OR lower(concat_ws(' ', r.surname, r.other_names, r.jamb_reg_no, r.application_no, r.admission_no, r.programme, r.open_reference)) LIKE CAST(:q AS text))
            """;
    private static final String COLUMNS = """
            r.application_id, r.application_no, r.jamb_reg_no, r.surname, r.other_names, r.programme, r.programme_code, r.faculty_code, r.faculty,
            r.dept_code, r.entry_mode, r.fee_due, r.paid_total, r.balance, r.excess, r.payments, r.first_amount, r.first_paid_at, r.last_paid_at,
            r.open_reference, r.open_amount, r.band, r.accepted_at, r.student_id, r.admission_no, r.letters_issued
            """;
    /** what the downloaded monitor carries */
    private static final String EXPORT_COLUMNS = """
            r.jamb_reg_no, r.application_no, r.surname, r.other_names, r.programme, r.faculty, r.entry_mode, r.fee_due, r.paid_total, r.balance,
            r.excess, r.payments, r.first_amount, r.first_paid_at, r.last_paid_at, r.open_reference, r.open_amount, r.band, r.admission_no, r.letters_issued
            """;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    AcceptanceFeeMonitorController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the filters as the monitor reads them — the faculty, department and programme already held to the office's scope;
     *  {@code search} as typed, for the record and the page, and its LIKE pattern for the query */
    record Filters(String band, String fac, String dept, String prog, String entry, String search) {
        String like() {
            return search == null ? null : "%" + search.toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        }

        /** the band left out: the tiles are counted with every other filter kept, so each stays a door */
        Filters anyBand() {
            return new Filters(null, fac, dept, prog, entry, search);
        }

        Map<String, Object> words() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("band", band == null ? "ALL" : band);
            if (fac != null) m.put("faculty", fac);
            if (dept != null) m.put("department", dept);
            if (prog != null) m.put("programme", prog);
            if (entry != null) m.put("entryMode", entry);
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

    private Filters filters(String band, String faculty, String dept, String programme, String entryMode, String q) {
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(dept), blank(programme));
        String bd = blank(band) == null ? null : band.trim().toUpperCase();
        if (bd != null && "ALL".equals(bd)) bd = null;
        if (bd != null && !BANDS.contains(bd)) throw new DomainRuleViolation("ACCEPTANCE_BAND", "'" + band + "' is not a band of the acceptance fee monitor.",
                new DomainRuleViolation.Remedy("Choose Not paid, Pending, Part paid, Settled in parts, Paid in full, Overpaid or Confirmed without a reference, or leave it for all.", "You"));
        String en = blank(entryMode) == null ? null : entryMode.trim().toUpperCase();
        if (en != null && !ENTRY_MODES.contains(en)) throw new DomainRuleViolation("ACCEPTANCE_ENTRY", "'" + entryMode + "' is not an entry mode of the monitor.",
                new DomainRuleViolation.Remedy("Choose UTME or Direct Entry, or leave it for both.", "You"));
        String search = blank(q);
        if (search != null && search.length() > 80) search = search.substring(0, 80);
        return new Filters(bd, b.fac(), b.dept(), b.prog(), en, search);
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, String s, Filters f) {
        return spec.param("s", s).param("band", f.band(), Types.VARCHAR).param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR)
                .param("prog", f.prog(), Types.VARCHAR).param("entry", f.entry(), Types.VARCHAR).param("q", f.like(), Types.VARCHAR);
    }

    /** a page of the offers the filters select, names A–Z */
    @GetMapping
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@PathVariable String session, @PathVariable String year,
                             @RequestParam(required = false) String band, @RequestParam(required = false) String faculty,
                             @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                             @RequestParam(required = false) String entryMode, @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String s = session(session, year);
        Filters f = filters(band, faculty, dept, programme, entryMode, q);
        int sz = Math.max(1, Math.min(size, 200)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql(ROWS + "SELECT count(*) OVER () AS total_rows, " + COLUMNS + " FROM r" + WHERE
                + " ORDER BY r.surname, r.other_names, r.application_id LIMIT :n OFFSET :o"), s, f)
                .param("n", sz).param("o", (long) pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", camel(rows));
        return out;
    }

    /** the figures above the monitor, from the very rows it reads: the offers, each band, those whose first payment was the
     *  figure before the revision, what is outstanding (every offer's unpaid obligation, the whole fee for an offer not yet paid),
     *  the balance to recover (V724: the part-paid offers' balances alone — what the revision left owing), the excess confirmed
     *  over the fee and what is collected — the band filter left out so each tile stays a door, every other filter kept; the fee
     *  as stated now and, when it was revised, the figure before and when */
    @GetMapping("/summary")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@PathVariable String session, @PathVariable String year,
                                @RequestParam(required = false) String band, @RequestParam(required = false) String faculty,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String programme,
                                @RequestParam(required = false) String entryMode, @RequestParam(required = false) String q) {
        String s = session(session, year);
        Filters f = filters(band, faculty, dept, programme, entryMode, q).anyBand();
        Map<String, Object> t = bind(jdbc.sql(ROWS + """
                SELECT count(*) AS offers,
                       count(*) FILTER (WHERE r.band = 'NOT_PAID') AS not_paid,
                       count(*) FILTER (WHERE r.band = 'PENDING') AS pending,
                       count(*) FILTER (WHERE r.band = 'PART_PAID') AS part_paid,
                       count(*) FILTER (WHERE r.band = 'SETTLED_IN_PARTS') AS settled_in_parts,
                       count(*) FILTER (WHERE r.band = 'PAID_IN_FULL') AS paid_in_full,
                       count(*) FILTER (WHERE r.band = 'OVERPAID') AS overpaid,
                       count(*) FILTER (WHERE r.band = 'CONFIRMED_WITHOUT_REFERENCE') AS confirmed_without_reference,
                       count(*) FILTER (WHERE r.first_amount IS NOT NULL AND r.first_amount < r.fee_due) AS paid_old_amount,
                       coalesce(sum(r.balance), 0) AS outstanding,
                       coalesce(sum(r.balance) FILTER (WHERE r.band = 'PART_PAID'), 0) AS outstanding_balance,
                       coalesce(sum(r.excess), 0) AS excess,
                       coalesce(sum(r.paid_total), 0) AS collected,
                       count(*) FILTER (WHERE r.letters_issued > 0) AS letters_issued,
                       count(*) FILTER (WHERE r.admission_no IS NOT NULL) AS on_register
                  FROM r""" + WHERE), s, f).query().singleRow();
        // the fee as stated now (admissions.applicant_fee_rule: the session's own, else carried forward) and the last revision of it
        Map<String, Object> fee = jdbc.sql("""
                SELECT (SELECT x.acceptance_fee FROM admissions.applicant_fee_rule(:s) x) AS fee_due,
                       v.previous_acceptance_fee AS previous_fee, v.stated_at AS revised_at, v.stated_office AS revised_office, v.reason AS revised_reason
                  FROM (SELECT 1) one
                  LEFT JOIN LATERAL (SELECT * FROM admissions.applicant_fee_revision x
                                      WHERE x.session = :s AND x.previous_acceptance_fee IS NOT NULL AND x.previous_acceptance_fee <> x.acceptance_fee
                                      ORDER BY x.stated_at DESC LIMIT 1) v ON true
                """).param("s", s).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("offers", t.get("offers"));
        out.put("notPaid", t.get("not_paid"));
        out.put("pending", t.get("pending"));
        out.put("partPaid", t.get("part_paid"));
        out.put("settledInParts", t.get("settled_in_parts"));
        out.put("paidInFull", t.get("paid_in_full"));
        out.put("overpaid", t.get("overpaid"));
        out.put("confirmedWithoutReference", t.get("confirmed_without_reference"));
        out.put("paidOldAmount", t.get("paid_old_amount"));
        out.put("outstanding", t.get("outstanding"));
        // V724: the recovery total — the balances the revision left on offers part paid — and what was confirmed over the fee
        out.put("outstandingBalance", t.get("outstanding_balance"));
        out.put("excess", t.get("excess"));
        out.put("collected", t.get("collected"));
        out.put("lettersIssued", t.get("letters_issued"));
        out.put("onRegister", t.get("on_register"));
        out.put("feeDue", fee.get("fee_due"));
        out.put("previousFee", fee.get("previous_fee"));
        out.put("revisedAt", fee.get("revised_at"));
        out.put("revisedOffice", fee.get("revised_office"));
        out.put("revisedReason", fee.get("revised_reason"));
        return out;
    }

    /** what the filter bar offers: the faculties and programmes of the session's released offers within the office's scope
     *  (one read of the monitor, grouped twice), the bands and the entry modes */
    @GetMapping("/options")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> options(@PathVariable String session, @PathVariable String year) {
        String s = session(session, year);
        OfficeScope.Bound b = scope.bound(null, null, null);
        List<Map<String, Object>> groups = jdbc.sql(ROWS + """
                SELECT grouping(r.programme_code) AS g_prog, r.faculty_code, r.faculty, r.programme_code, r.programme, count(*) AS n
                  FROM r
                 WHERE (CAST(:fac AS text) IS NULL OR r.faculty_code = CAST(:fac AS text))
                   AND (CAST(:dept AS text) IS NULL OR r.dept_code = CAST(:dept AS text))
                   AND (CAST(:prog AS text) IS NULL OR r.programme_code = CAST(:prog AS text))
                 GROUP BY GROUPING SETS ((r.faculty_code, r.faculty), (r.faculty_code, r.faculty, r.programme_code, r.programme))
                 ORDER BY r.faculty, r.programme
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().listOfRows();
        List<Map<String, Object>> faculties = new ArrayList<>(), programmes = new ArrayList<>();
        for (Map<String, Object> g : groups) {
            Map<String, Object> row = new LinkedHashMap<>();
            if (((Number) g.get("g_prog")).intValue() == 0) {
                if (g.get("programme_code") == null) continue;   // an offer whose programme the register does not name
                row.put("code", g.get("programme_code"));
                row.put("name", g.get("programme"));
                row.put("faculty", g.get("faculty_code"));
                row.put("offers", g.get("n"));
                programmes.add(row);
            } else {
                if (g.get("faculty_code") == null) continue;
                row.put("code", g.get("faculty_code"));
                row.put("name", g.get("faculty"));
                row.put("offers", g.get("n"));
                faculties.add(row);
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", jdbc.sql("SELECT DISTINCT a.session FROM admissions.application a ORDER BY 1 DESC").query(String.class).list());
        out.put("faculties", faculties);
        out.put("programmes", programmes);
        out.put("bands", BANDS);
        out.put("entryModes", List.of("UTME", "DIRECT_ENTRY"));
        out.put("scope", scopeMap());
        return out;
    }

    record ExportIn(@NotBlank @Pattern(regexp = "XLSX|PDF") String format, String band, String faculty, String dept, String programme, String entryMode,
                    @Size(max = 80) String q) {
    }

    /** every offer the filters select, names A–Z, for the Excel and PDF engine — and the download recorded on the audit
     *  spine: who, when, the session, the format, the filters and the number of rows */
    @PostMapping("/export")
    @PreAuthorize(VIEWERS)
    @Transactional
    Map<String, Object> export(@PathVariable String session, @PathVariable String year, @Valid @RequestBody ExportIn body) {
        String s = session(session, year);
        Filters f = filters(body.band(), body.faculty(), body.dept(), body.programme(), body.entryMode(), body.q());
        List<Map<String, Object>> rows = bind(jdbc.sql(ROWS + "SELECT " + EXPORT_COLUMNS + " FROM r" + WHERE
                + " ORDER BY r.surname, r.other_names, r.application_id"), s, f).query().listOfRows();
        AuditContext ctx = AuditContextHolder.required();
        Map<String, Object> words = f.words();
        jdbc.sql("""
                INSERT INTO admissions.report_export (report, session, format, filters, row_count, exported_by, office)
                VALUES (:r, :s, :fmt,
                        jsonb_strip_nulls(jsonb_build_object('band', CAST(:band AS text), 'faculty', CAST(:fac AS text), 'department', CAST(:dept AS text),
                            'programme', CAST(:prog AS text), 'entryMode', CAST(:entry AS text), 'search', CAST(:search AS text))),
                        :n, :by, (SELECT o.code FROM ref.office o WHERE o.code = CAST(:office AS text)))
                """).param("r", REPORT).param("s", s).param("fmt", body.format()).param("band", String.valueOf(words.get("band")))
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("entry", f.entry(), Types.VARCHAR).param("search", f.search(), Types.VARCHAR).param("n", rows.size())
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
        out.put("rows", camel(rows));
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

    private Map<String, Object> scopeMap() {
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("faculty", b.fac());
        m.put("department", b.dept());
        m.put("programme", b.prog());
        return m;
    }

    /* ── the monitor's columns in camelCase, as the contract names them ── */

    private static List<Map<String, Object>> camel(List<Map<String, Object>> rows) {
        List<Map<String, Object>> out = new ArrayList<>(rows.size());
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>();
            r.forEach((k, v) -> m.put(camel(k), v));
            out.add(m);
        }
        return out;
    }

    private static String camel(String key) {
        StringBuilder b = new StringBuilder(key.length());
        boolean up = false;
        for (char c : key.toCharArray()) {
            if (c == '_') {
                up = true;
                continue;
            }
            b.append(up ? Character.toUpperCase(c) : c);
            up = false;
        }
        return b.toString();
    }
}
