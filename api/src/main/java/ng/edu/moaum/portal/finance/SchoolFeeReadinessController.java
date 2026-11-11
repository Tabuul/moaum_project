package ng.edu.moaum.portal.finance;

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
 * The school-fee readiness monitor (V724): whether the school fees of a session reach its fresh undergraduate entrants, and
 * where each fresher stands at the student portal's fee gate. Two reads of the database hold the rules once: the census,
 * finance.programme_fee_coverage — every undergraduate programme with or without a full-time fee line in force reaching a
 * UTME (100 Level) or Direct Entry (200 Level) entrant of the session, and the freshers of the session on its register — and
 * the roll, finance.intake_fee_monitor — every UTME or Direct Entry fresher of the session on the register with what the
 * fees say (stated or not, due, the first semester's due, paid, the balance, a reference awaiting the bank, the state), the
 * acceptance fee balance still owed, whether an applicant account exists to pay from, and the gate's word (OPEN, EXCEPTION,
 * HELD_ACCEPTANCE_BALANCE, CLEARED, HELD_FEES_NOT_AVAILABLE, HELD_FEES_UNPAID). Each request reads the roll once (a
 * materialised CTE), filters and pages in SQL, and counts its figures from the same rows.
 *
 * <p>Two words for "cleared", kept apart (V724): a row's {@code cleared} is the gate's rule applied to the fees
 * (finance.portal_fee_gate.clears_on: the first semester's fees, or the session's in full), whether or not the gate reaches the
 * student — a fresher already matriculated still reads cleared or not by what they have paid; the summary's {@code cleared} and
 * {@code notCleared} count the gate as it stands — cleared when the portal is open to the student (CLEARED, EXCEPTION, OPEN), not
 * cleared while it holds them (HELD_…) — so the two tiles add up to the freshers and say who can reach the portal now. Read by
 * the Bursary, the Students Account Officer, the Directorate of ICT, the platform, the Academic Office, the Registry and the audit
 * directorate; each download recorded on the audit spine (admissions.report_export).
 */
@RestController
@RequestMapping("/api/v1/finance/sessions/{session}/{year}/intake-fees")
class SchoolFeeReadinessController {

    static final String VIEWERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_ict','OFFICE_admin','OFFICE_super','OFFICE_academic',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_audit','OFFICE_deputyaudit')";
    static final String REPORT = "INTAKE_FEE_READINESS";
    /** the fee states, in the order the tiles stand: nothing stated first */
    static final List<String> FEE_STATES = List.of("NOT_CONFIGURED", "AVAILABLE", "NOT_OPEN", "PAYMENT_PENDING", "PART_PAID", "PAID");
    /** the gate's states, in the order the tiles stand: held first — the acceptance fee balance before the school fees, as
     *  finance.portal_access_state reads them (V724) */
    static final List<String> PORTAL_STATES = List.of("HELD_ACCEPTANCE_BALANCE", "HELD_FEES_NOT_AVAILABLE", "HELD_FEES_UNPAID", "CLEARED", "EXCEPTION", "OPEN");
    private static final Set<String> ENTRY_MODES = Set.of("UTME", "DIRECT_ENTRY");

    /** the roll read once a request: its rows with the programme's department, the faculty's name, and whether the fees meet the
     *  gate's rule (the one row of finance.portal_fee_gate, seeded at V724) — materialised, so the monitor is evaluated exactly once
     *  however the statement reads it (the summary groups it three ways, the page counts it beside the page) */
    private static final String ROWS = """
            WITH g AS (SELECT clears_on FROM finance.portal_fee_gate WHERE id = 1),
            r AS MATERIALIZED (
                SELECT m.*, pr.dept_code, fa.name AS faculty,
                       CASE g.clears_on WHEN 'PAID_IN_FULL' THEN m.paid_in_full ELSE m.first_semester_cleared END AS cleared
                  FROM finance.intake_fee_monitor(:s) m
                  CROSS JOIN g
                  LEFT JOIN ref.programme pr ON pr.code = m.programme_code
                  LEFT JOIN ref.faculty fa ON fa.code = m.faculty_code)
            """;
    /** the filters, every one a bound parameter */
    private static final String WHERE = """
             WHERE (CAST(:fee AS text) IS NULL OR r.fee_state = CAST(:fee AS text))
               AND (CAST(:portal AS text) IS NULL OR r.portal_state = CAST(:portal AS text))
               AND (CAST(:fac AS text) IS NULL OR r.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR r.dept_code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR r.programme_code = CAST(:prog AS text))
               AND (CAST(:entry AS text) IS NULL OR r.entry_mode = CAST(:entry AS text))
               AND (CAST(:q AS text) IS NULL
                    OR lower(concat_ws(' ', r.surname, r.other_names, r.admission_no, r.matric_no, r.programme, r.open_reference)) LIKE CAST(:q AS text))
            """;
    private static final String COLUMNS = """
            r.student_id, r.admission_no, r.matric_no, r.surname, r.other_names, r.programme_code, r.programme, r.faculty_code, r.faculty, r.dept_code,
            r.entry_mode, r.current_level, r.status, r.fee_stated, r.due, r.due_first_semester, r.paid, r.balance, r.paid_in_full,
            r.first_semester_cleared, r.cleared, r.open_reference, r.fee_state, r.acceptance_balance, r.has_applicant_account, r.portal_state,
            r.account_opened, r.last_signed_in_at
            """;
    /** what the downloaded monitor carries */
    private static final String EXPORT_COLUMNS = """
            r.admission_no, r.matric_no, r.surname, r.other_names, r.programme, r.faculty, r.entry_mode, r.current_level, r.status, r.fee_stated,
            r.due, r.due_first_semester, r.paid, r.balance, r.paid_in_full, r.first_semester_cleared, r.cleared, r.open_reference, r.fee_state,
            r.acceptance_balance, r.has_applicant_account, r.portal_state, r.account_opened, r.last_signed_in_at
            """;
    /** the census within the office's scope: the coverage rows with the programme's department */
    private static final String COVERAGE = """
            WITH c AS (
                SELECT x.*, pr.dept_code
                  FROM finance.programme_fee_coverage(:s) x
                  LEFT JOIN ref.programme pr ON pr.code = x.programme_code)
            """;
    private static final String COVERAGE_WHERE = """
             WHERE (CAST(:fac AS text) IS NULL OR c.faculty_code = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR c.dept_code = CAST(:dept AS text))
               AND (CAST(:prog AS text) IS NULL OR c.programme_code = CAST(:prog AS text))
            """;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    SchoolFeeReadinessController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the filters as the monitor reads them — the faculty, department and programme already held to the office's scope;
     *  {@code search} as typed, for the record and the page, and its LIKE pattern for the query */
    record Filters(String fee, String portal, String fac, String dept, String prog, String entry, String search) {
        String like() {
            return search == null ? null : "%" + search.toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        }

        /** the two state filters left out: the tiles are counted with every other filter kept, so each stays a door */
        Filters anyState() {
            return new Filters(null, null, fac, dept, prog, entry, search);
        }

        Map<String, Object> words() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("feeState", fee == null ? "ALL" : fee);
            m.put("portalState", portal == null ? "ALL" : portal);
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
        if (!s.matches("\\d{4}/\\d{4}")) throw new DomainRuleViolation("FEE_SESSION", "A session is named YYYY/YYYY.",
                new DomainRuleViolation.Remedy("Choose the admission session whose freshers the monitor reads.", "Bursary"));
        return s;
    }

    private Filters filters(String feeState, String portalState, String faculty, String dept, String programme, String entryMode, String q) {
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(dept), blank(programme));
        String fs = blank(feeState) == null ? null : feeState.trim().toUpperCase();
        if (fs != null && "ALL".equals(fs)) fs = null;
        if (fs != null && !FEE_STATES.contains(fs)) throw new DomainRuleViolation("INTAKE_FEE_STATE", "'" + feeState + "' is not a fee state of the monitor.",
                new DomainRuleViolation.Remedy("Choose Not configured, Available, Not open, Payment pending, Part paid or Paid, or leave it for all.", "You"));
        String ps = blank(portalState) == null ? null : portalState.trim().toUpperCase();
        if (ps != null && "ALL".equals(ps)) ps = null;
        if (ps != null && !PORTAL_STATES.contains(ps)) throw new DomainRuleViolation("INTAKE_PORTAL_STATE", "'" + portalState + "' is not a state of the portal fee gate.",
                new DomainRuleViolation.Remedy("Choose Held (acceptance fee balance), Held (fees not available), Held (fees unpaid), Cleared, Exception or Open, or leave it for all.", "You"));
        String en = blank(entryMode) == null ? null : entryMode.trim().toUpperCase();
        if (en != null && !ENTRY_MODES.contains(en)) throw new DomainRuleViolation("INTAKE_ENTRY", "'" + entryMode + "' is not an entry mode of the monitor.",
                new DomainRuleViolation.Remedy("Choose UTME or Direct Entry, or leave it for both.", "You"));
        String search = blank(q);
        if (search != null && search.length() > 80) search = search.substring(0, 80);
        return new Filters(fs, ps, b.fac(), b.dept(), b.prog(), en, search);
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, String s, Filters f) {
        return spec.param("s", s).param("fee", f.fee(), Types.VARCHAR).param("portal", f.portal(), Types.VARCHAR).param("fac", f.fac(), Types.VARCHAR)
                .param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR).param("entry", f.entry(), Types.VARCHAR)
                .param("q", f.like(), Types.VARCHAR);
    }

    /** the gate as it stands, for the screen to say which rule "cleared" follows */
    private Map<String, Object> gate() {
        Map<String, Object> g = jdbc.sql("SELECT enabled, from_session, clears_on FROM finance.portal_fee_gate WHERE id = 1").query().singleRow();
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("enabled", g.get("enabled"));
        m.put("fromSession", g.get("from_session"));
        m.put("clearsOn", g.get("clears_on"));
        return m;
    }

    /** the census: every undergraduate programme × entry (UTME 100 Level, Direct Entry 200 Level) within the office's scope, whether a
     *  fee line reaches it, how many lines, and the freshers of the session on the register; the figures by programme (covered when
     *  every entry of it is, uncovered otherwise, and uncovered with freshers on the register — the gap that holds students) and by
     *  faculty. {@code uncoveredOnly} keeps the rows without a line */
    @GetMapping("/coverage")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> coverage(@PathVariable String session, @PathVariable String year,
                                 @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                                 @RequestParam(required = false) String programme, @RequestParam(defaultValue = "false") boolean uncoveredOnly) {
        String s = session(session, year);
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(dept), blank(programme));
        List<Map<String, Object>> rows = jdbc.sql(COVERAGE + "SELECT c.faculty_code, c.faculty, c.programme_code, c.programme, c.dept_code, c.entry_mode, c.level, "
                + "c.covered, c.lines, c.admitted FROM c" + COVERAGE_WHERE + " AND (NOT CAST(:only AS boolean) OR NOT c.covered)"
                + " ORDER BY c.faculty, c.programme, c.level")
                .param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .param("only", uncoveredOnly).query().listOfRows();
        List<Map<String, Object>> groups = jdbc.sql(COVERAGE + """
                , p AS (
                    SELECT c.faculty_code, c.faculty, c.programme_code,
                           bool_and(c.covered) AS covered, bool_or(NOT c.covered AND c.admitted > 0) AS gap, sum(c.admitted) AS freshers
                      FROM c""" + COVERAGE_WHERE + """
                     GROUP BY 1, 2, 3)
                SELECT grouping(p.faculty_code) AS g_fac, p.faculty_code, p.faculty,
                       count(*) AS programmes, count(*) FILTER (WHERE p.covered) AS covered, count(*) FILTER (WHERE NOT p.covered) AS uncovered,
                       count(*) FILTER (WHERE p.gap) AS uncovered_with_freshers, coalesce(sum(p.freshers), 0) AS freshers
                  FROM p
                 GROUP BY GROUPING SETS ((), (p.faculty_code, p.faculty))
                 ORDER BY p.faculty
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("scope", scopeMap());
        List<Map<String, Object>> byFaculty = new ArrayList<>();
        long programmes = 0, covered = 0, uncovered = 0, gap = 0, freshers = 0;
        for (Map<String, Object> g : groups) {
            if (((Number) g.get("g_fac")).intValue() == 1) {
                programmes = ((Number) g.get("programmes")).longValue();
                covered = ((Number) g.get("covered")).longValue();
                uncovered = ((Number) g.get("uncovered")).longValue();
                gap = ((Number) g.get("uncovered_with_freshers")).longValue();
                freshers = ((Number) g.get("freshers")).longValue();
                continue;
            }
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("code", g.get("faculty_code"));
            row.put("name", g.get("faculty"));
            row.put("programmes", g.get("programmes"));
            row.put("covered", g.get("covered"));
            row.put("uncovered", g.get("uncovered"));
            row.put("uncoveredWithFreshers", g.get("uncovered_with_freshers"));
            row.put("freshers", g.get("freshers"));
            byFaculty.add(row);
        }
        out.put("programmes", programmes);
        out.put("covered", covered);
        out.put("uncovered", uncovered);
        out.put("uncoveredWithFreshers", gap);
        out.put("freshers", freshers);
        out.put("rows", camel(rows));
        out.put("byFaculty", byFaculty);
        return out;
    }

    /** the figures above the roll, from the very rows it reads: the freshers, each fee state and each gate state (every key present,
     *  zero when none), cleared and not as the gate stands (V724: the portal open to the student — CLEARED, EXCEPTION, OPEN — or
     *  held, so the two add up to the freshers), the accounts opened and signed in, and the money — the two state filters left out
     *  so each tile stays a door, every other filter kept */
    @GetMapping("/summary")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@PathVariable String session, @PathVariable String year,
                                @RequestParam(required = false) String feeState, @RequestParam(required = false) String portalState,
                                @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                                @RequestParam(required = false) String programme, @RequestParam(required = false) String entryMode,
                                @RequestParam(required = false) String q) {
        String s = session(session, year);
        Filters f = filters(feeState, portalState, faculty, dept, programme, entryMode, q).anyState();
        // one read of the roll, grouped three ways: in all, by fee state, by gate state
        List<Map<String, Object>> groups = bind(jdbc.sql(ROWS + """
                SELECT grouping(r.fee_state) AS g_fee, grouping(r.portal_state) AS g_portal, r.fee_state, r.portal_state,
                       count(*) AS n,
                       count(*) FILTER (WHERE r.portal_state IN ('CLEARED', 'EXCEPTION', 'OPEN')) AS cleared,
                       count(*) FILTER (WHERE r.portal_state LIKE 'HELD%') AS not_cleared,
                       count(*) FILTER (WHERE r.account_opened) AS accounts_opened, count(*) FILTER (WHERE r.last_signed_in_at IS NOT NULL) AS signed_in,
                       count(*) FILTER (WHERE r.fee_stated) AS fee_stated,
                       coalesce(sum(r.due), 0) AS due, coalesce(sum(r.paid), 0) AS collected, coalesce(sum(r.balance), 0) AS outstanding
                  FROM r""" + WHERE + """
                 GROUP BY GROUPING SETS ((), (r.fee_state), (r.portal_state))
                """), s, f).query().listOfRows();
        Map<String, Object> feeStates = new LinkedHashMap<>(), portalStates = new LinkedHashMap<>();
        FEE_STATES.forEach(k -> feeStates.put(k, 0L));
        PORTAL_STATES.forEach(k -> portalStates.put(k, 0L));
        Map<String, Object> all = Map.of();
        for (Map<String, Object> g : groups) {
            boolean byFee = ((Number) g.get("g_fee")).intValue() == 0, byPortal = ((Number) g.get("g_portal")).intValue() == 0;
            if (byFee) feeStates.put(String.valueOf(g.get("fee_state")), g.get("n"));
            else if (byPortal) portalStates.put(String.valueOf(g.get("portal_state")), g.get("n"));
            else all = g;
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("gate", gate());
        out.put("freshers", all.getOrDefault("n", 0L));
        out.put("feeStates", feeStates);
        out.put("portalStates", portalStates);
        out.put("cleared", all.getOrDefault("cleared", 0L));
        out.put("notCleared", all.getOrDefault("not_cleared", 0L));
        out.put("feeStated", all.getOrDefault("fee_stated", 0L));
        out.put("accountsOpened", all.getOrDefault("accounts_opened", 0L));
        out.put("signedIn", all.getOrDefault("signed_in", 0L));
        out.put("due", all.getOrDefault("due", java.math.BigDecimal.ZERO));
        out.put("collected", all.getOrDefault("collected", java.math.BigDecimal.ZERO));
        out.put("outstanding", all.getOrDefault("outstanding", java.math.BigDecimal.ZERO));
        return out;
    }

    /** a page of the freshers the filters select, names A–Z */
    @GetMapping
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@PathVariable String session, @PathVariable String year,
                             @RequestParam(required = false) String feeState, @RequestParam(required = false) String portalState,
                             @RequestParam(required = false) String faculty, @RequestParam(required = false) String dept,
                             @RequestParam(required = false) String programme, @RequestParam(required = false) String entryMode,
                             @RequestParam(required = false) String q,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String s = session(session, year);
        Filters f = filters(feeState, portalState, faculty, dept, programme, entryMode, q);
        int sz = Math.max(1, Math.min(size, 200)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql(ROWS + "SELECT count(*) OVER () AS total_rows, " + COLUMNS + " FROM r" + WHERE
                + " ORDER BY r.surname, r.other_names, r.student_id LIMIT :n OFFSET :o"), s, f)
                .param("n", sz).param("o", (long) pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("gate", gate());
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", camel(rows));
        return out;
    }

    /** what the filter bar offers: the sessions on the calendar and the intake session, the faculties and programmes with freshers
     *  of the session on the register within the office's scope (from the census, which is light — the roll is not read for a
     *  filter bar), the fee states, the gate's states and the entry modes */
    @GetMapping("/options")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> options(@PathVariable String session, @PathVariable String year) {
        String s = session(session, year);
        OfficeScope.Bound b = scope.bound(null, null, null);
        List<Map<String, Object>> groups = jdbc.sql(COVERAGE + """
                SELECT grouping(c.programme_code) AS g_prog, c.faculty_code, c.faculty, c.programme_code, c.programme, sum(c.admitted) AS freshers
                  FROM c""" + COVERAGE_WHERE + """
                   AND c.admitted > 0
                 GROUP BY GROUPING SETS ((c.faculty_code, c.faculty), (c.faculty_code, c.faculty, c.programme_code, c.programme))
                 ORDER BY c.faculty, c.programme
                """).param("s", s).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).param("prog", b.prog(), Types.VARCHAR)
                .query().listOfRows();
        List<Map<String, Object>> faculties = new ArrayList<>(), programmes = new ArrayList<>();
        for (Map<String, Object> g : groups) {
            Map<String, Object> row = new LinkedHashMap<>();
            if (((Number) g.get("g_prog")).intValue() == 0) {
                row.put("code", g.get("programme_code"));
                row.put("name", g.get("programme"));
                row.put("faculty", g.get("faculty_code"));
                row.put("freshers", g.get("freshers"));
                programmes.add(row);
            } else {
                row.put("code", g.get("faculty_code"));
                row.put("name", g.get("faculty"));
                row.put("freshers", g.get("freshers"));
                faculties.add(row);
            }
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("intake", jdbc.sql("SELECT policy.intake_session()").query(String.class).optional().orElse(null));
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session ORDER BY name DESC").query(String.class).list());
        out.put("faculties", faculties);
        out.put("programmes", programmes);
        out.put("feeStates", FEE_STATES);
        out.put("portalStates", PORTAL_STATES);
        out.put("entryModes", List.of("UTME", "DIRECT_ENTRY"));
        out.put("gate", gate());
        out.put("scope", scopeMap());
        return out;
    }

    record ExportIn(@NotBlank @Pattern(regexp = "XLSX|PDF") String format, String feeState, String portalState, String faculty, String dept,
                    String programme, String entryMode, @Size(max = 80) String q) {
    }

    /** every fresher the filters select, names A–Z, for the Excel and PDF engine — and the download recorded on the audit spine:
     *  who, when, the session, the format, the filters and the number of rows */
    @PostMapping("/export")
    @PreAuthorize(VIEWERS)
    @Transactional
    Map<String, Object> export(@PathVariable String session, @PathVariable String year, @Valid @RequestBody ExportIn body) {
        String s = session(session, year);
        Filters f = filters(body.feeState(), body.portalState(), body.faculty(), body.dept(), body.programme(), body.entryMode(), body.q());
        List<Map<String, Object>> rows = bind(jdbc.sql(ROWS + "SELECT " + EXPORT_COLUMNS + " FROM r" + WHERE
                + " ORDER BY r.surname, r.other_names, r.student_id"), s, f).query().listOfRows();
        AuditContext ctx = AuditContextHolder.required();
        Map<String, Object> words = f.words();
        jdbc.sql("""
                INSERT INTO admissions.report_export (report, session, format, filters, row_count, exported_by, office)
                VALUES (:r, :s, :fmt,
                        jsonb_strip_nulls(jsonb_build_object('feeState', CAST(:fee AS text), 'portalState', CAST(:portal AS text),
                            'faculty', CAST(:fac AS text), 'department', CAST(:dept AS text), 'programme', CAST(:prog AS text),
                            'entryMode', CAST(:entry AS text), 'search', CAST(:search AS text))),
                        :n, :by, (SELECT o.code FROM ref.office o WHERE o.code = CAST(:office AS text)))
                """).param("r", REPORT).param("s", s).param("fmt", body.format())
                .param("fee", String.valueOf(words.get("feeState"))).param("portal", String.valueOf(words.get("portalState")))
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("entry", f.entry(), Types.VARCHAR).param("search", f.search(), Types.VARCHAR).param("n", rows.size())
                .param("by", ctx.actorId()).param("office", ctx.actorOffice(), Types.VARCHAR).update();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("format", body.format());
        out.put("filters", words);
        out.put("labels", labels(f));
        out.put("scope", scopeMap());
        out.put("gate", gate());
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
