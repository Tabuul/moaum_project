package ng.edu.moaum.portal.transfers;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

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
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * The inter-departmental transfer fee monitor (V727): every transfer application of a session (not the withdrawn) with the fee as
 * stated now, what is paid on this portal and on the old portal, the balance, any excess, whether a payment awaits the bank, a band
 * (NOT_PAID, PENDING, PART_PAID, SETTLED_IN_PARTS, PAID_IN_FULL, OVERPAID, NO_FEE, FEE_NOT_STATED, and CLOSED for a declined or not
 * recommended application, which owes nothing more) and what it awaits (PAYMENT, a desk, DONE) — and every student whose old-portal
 * transfer payments await an application (band AWAITING_APPLICATION). What is owed is read over the live applications alone. One read of
 * people.transfer_fee_monitor a request, in a materialised CTE, filtered in SQL; the figures above the list counted from the same
 * rows; the filtered set handed to the portal's Excel and PDF engine, each download recorded (admissions.report_export, report
 * TRANSFER_FEES). The acceptance fee monitor's shape (admissions/AcceptanceFeeMonitorController).
 *
 * <p>Read by the Academic Office, the Registry, ICT, the Bursary, the Students Account Officer, the Vice-Chancellor's offices and
 * the platform university-wide; a Head of Department sees the applications from or to the department, a Dean those from or to the
 * faculty — the scope the server holds (OfficeScope.bound), whatever the request names.
 */
@RestController
@RequestMapping("/api/v1/transfers/fees")
class TransferFeeMonitorController {

    static final String VIEWERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_bursar','OFFICE_studentaccounts',"
            + "'OFFICE_hod','OFFICE_dean','OFFICE_dvc','OFFICE_vc','OFFICE_admin','OFFICE_super')";
    static final String REPORT = "TRANSFER_FEES";
    /** the bands, owing first; then settled, more than settled; then the bands with nothing to pay (CLOSED: declined or not
     *  recommended, nothing more owed) and the credit awaiting an application */
    static final List<String> BANDS = List.of("NOT_PAID", "PENDING", "PART_PAID", "SETTLED_IN_PARTS", "PAID_IN_FULL", "OVERPAID", "NO_FEE", "FEE_NOT_STATED",
            "CLOSED", "AWAITING_APPLICATION");
    /** what an application awaits, in the order of the desks; DECLINED stands for none (declined or not recommended) */
    static final List<String> AWAITING = List.of("PAYMENT", "CURRENT_HOD", "NEW_HOD", "REGISTRY", "ACADEMIC_OFFICE", "SENATE", "REGISTRY_EFFECT", "DONE",
            "APPLICATION", "DECLINED");

    /** the monitor read once a request, with the faculty of each department it names (a Dean's bound) and the faculty's name */
    private static final String ROWS = """
            WITH r AS MATERIALIZED (
                SELECT m.*, fd.faculty_code AS from_faculty, coalesce(td.faculty_code, m.faculty_code) AS to_faculty, fa.name AS faculty
                  FROM people.transfer_fee_monitor(CAST(:s AS text)) m
                  LEFT JOIN ref.department fd ON fd.code = m.from_dept
                  LEFT JOIN ref.department td ON td.code = m.to_dept
                  LEFT JOIN ref.faculty fa ON fa.code = m.faculty_code)
            """;
    /** the scope and the filters; a department or faculty matches the application's either side */
    private static final String SCOPE = """
             WHERE (CAST(:fac AS text) IS NULL OR r.faculty_code = CAST(:fac AS text) OR r.from_faculty = CAST(:fac AS text) OR r.to_faculty = CAST(:fac AS text))
               AND (CAST(:dept AS text) IS NULL OR r.from_dept = CAST(:dept AS text) OR r.to_dept = CAST(:dept AS text))
               AND (CAST(:q AS text) IS NULL
                    OR lower(concat_ws(' ', r.matric_no, r.name, r.from_programme, r.to_programme, r.legacy_ref)) LIKE CAST(:q AS text))
            """;
    private static final String BAND_AND_AWAITING = """
               AND (CAST(:band AS text) IS NULL OR r.band = CAST(:band AS text))
               AND (CAST(:aw AS text) IS NULL OR coalesce(r.awaiting, 'DECLINED') = CAST(:aw AS text))
            """;
    private static final String COLUMNS = """
            r.application_id, r.student_id, r.matric_no, r.name, r.session, r.from_programme, r.to_programme, r.faculty_code, r.faculty,
            r.from_dept, r.to_dept, r.state, r.awaiting, r.legacy_ref, r.fee_due, r.portal_paid, r.old_portal_paid, r.paid_total, r.balance,
            r.excess, r.payments, r.pending, r.band, r.applied_at
            """;

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    TransferFeeMonitorController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    /** the filters as the monitor reads them — the faculty and department already held to the office's scope; {@code search} as
     *  typed, for the record and the page, and its LIKE pattern for the query */
    record Filters(String session, String band, String awaiting, String fac, String dept, String search) {
        String like() {
            return search == null ? null : "%" + search.toLowerCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        }

        Map<String, Object> words() {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("session", session == null ? "ALL" : session);
            m.put("band", band == null ? "ALL" : band);
            m.put("awaiting", awaiting == null ? "ALL" : awaiting);
            if (fac != null) m.put("faculty", fac);
            if (dept != null) m.put("department", dept);
            if (search != null) m.put("search", search);
            return m;
        }
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    /** the session read: one named (YYYY/YYYY), ALL for every session, else the University's current session — never a literal */
    private String session(String session) {
        String s = blank(session);
        if (s == null) {
            return jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
        }
        if ("ALL".equalsIgnoreCase(s)) return null;
        if (!s.matches("\\d{4}/\\d{4}")) throw new DomainRuleViolation("TRANSFER_FEES_SESSION", "A session is named YYYY/YYYY.",
                new DomainRuleViolation.Remedy("Choose the session, or All sessions.", "You"));
        return s;
    }

    private Filters filters(String session, String band, String awaiting, String faculty, String dept, String q) {
        OfficeScope.Bound b = scope.bound(blank(faculty), blank(dept), null);
        String bd = blank(band) == null ? null : band.trim().toUpperCase();
        if ("ALL".equals(bd)) bd = null;
        if (bd != null && !BANDS.contains(bd)) throw new DomainRuleViolation("TRANSFER_FEES_BAND", "'" + band + "' is not a band of the transfer fee monitor.",
                new DomainRuleViolation.Remedy("Choose a payment status from the bar, or leave it for all.", "You"));
        String aw = blank(awaiting) == null ? null : awaiting.trim().toUpperCase();
        if ("ALL".equals(aw)) aw = null;
        if (aw != null && !AWAITING.contains(aw)) throw new DomainRuleViolation("TRANSFER_FEES_AWAITING", "'" + awaiting + "' is not a stage of the transfer fee monitor.",
                new DomainRuleViolation.Remedy("Choose what the applications await from the bar, or leave it for all.", "You"));
        String search = blank(q);
        if (search != null && search.length() > 80) search = search.substring(0, 80);
        return new Filters(session(session), bd, aw, b.fac(), b.dept(), search);
    }

    private static JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, Filters f) {
        return spec.param("s", f.session(), Types.VARCHAR).param("band", f.band(), Types.VARCHAR).param("aw", f.awaiting(), Types.VARCHAR)
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("q", f.like(), Types.VARCHAR);
    }

    /** a page of the applications the filters select, names A–Z */
    @GetMapping
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> list(@RequestParam(required = false) String session, @RequestParam(required = false) String band,
                             @RequestParam(required = false) String awaiting, @RequestParam(required = false) String faculty,
                             @RequestParam(required = false) String dept, @RequestParam(required = false) String search,
                             @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "200") int size) {
        Filters f = filters(session, band, awaiting, faculty, dept, search);
        int sz = Math.max(1, Math.min(size, 1000)), pg = Math.max(0, page);
        List<Map<String, Object>> rows = bind(jdbc.sql(ROWS + "SELECT count(*) OVER () AS total_rows, " + COLUMNS + " FROM r" + SCOPE + BAND_AND_AWAITING
                + " ORDER BY r.name, r.applied_at, r.application_id LIMIT :n OFFSET :o"), f)
                .param("n", sz).param("o", (long) pg * sz).query().listOfRows();
        long total = rows.isEmpty() ? 0 : ((Number) rows.get(0).get("total_rows")).longValue();
        rows.forEach(r -> r.remove("total_rows"));
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", f.session());
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    /** the figures above the monitor, from the very rows it reads — the band and the stage left out so each tile stays a door, the
     *  scope, faculty, department and search kept: the applications by band and by what they await; what is owed — the balance, the
     *  applications still owing and those with nothing paid — on the live applications alone (nothing is owed until an application
     *  exists, nor once it is effected or closed); what is collected here and on the old portal, the excess; those ready for the final
     *  approval (with the Academic Office, the fee stated and nothing owed — people.transfer_fee_settled_or_refuse: a payment awaiting
     *  the bank no longer matters once nothing is owed); the old-portal credits awaiting an application, the old-portal payments not
     *  matched; the fee as stated now and its last revision */
    @GetMapping("/summary")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                                @RequestParam(required = false) String dept, @RequestParam(required = false) String search) {
        Filters f = filters(session, null, null, faculty, dept, search);
        List<Map<String, Object>> groups = bind(jdbc.sql(ROWS + """
                SELECT grouping(r.band) AS g_band, grouping(coalesce(r.awaiting, 'DECLINED')) AS g_aw, r.band, coalesce(r.awaiting, 'DECLINED') AS awaiting,
                       count(*) AS n,
                       count(*) FILTER (WHERE r.application_id IS NOT NULL) AS applications,
                       coalesce(sum(r.balance) FILTER (WHERE r.application_id IS NOT NULL AND r.state = ANY (people.transfer_live_states())), 0) AS outstanding,
                       count(*) FILTER (WHERE r.application_id IS NOT NULL AND r.state = ANY (people.transfer_live_states()) AND r.balance > 0) AS still_owing,
                       count(*) FILTER (WHERE r.application_id IS NOT NULL AND r.state = ANY (people.transfer_live_states()) AND r.balance > 0
                                          AND coalesce(r.paid_total, 0) = 0) AS not_paid,
                       coalesce(sum(r.portal_paid), 0) AS collected_portal,
                       coalesce(sum(r.old_portal_paid), 0) AS collected_old_portal,
                       coalesce(sum(r.excess), 0) AS excess,
                       count(*) FILTER (WHERE r.state = 'REG_OK' AND r.fee_due IS NOT NULL AND r.balance <= 0) AS ready_final,
                       count(*) FILTER (WHERE r.application_id IS NULL) AS awaiting_application
                  FROM r""" + SCOPE + """
                 GROUP BY GROUPING SETS ((), (r.band), (coalesce(r.awaiting, 'DECLINED')))
                """), f).query().listOfRows();
        Map<String, Object> bands = new LinkedHashMap<>(), awaiting = new LinkedHashMap<>();
        for (String b : BANDS) bands.put(b, 0);
        for (String a : AWAITING) awaiting.put(a, 0);
        Map<String, Object> all = Map.of();
        for (Map<String, Object> g : groups) {
            boolean byBand = ((Number) g.get("g_band")).intValue() == 0, byAwaiting = ((Number) g.get("g_aw")).intValue() == 0;
            if (byBand && g.get("band") != null) bands.put(String.valueOf(g.get("band")), ((Number) g.get("n")).intValue());
            else if (byAwaiting) awaiting.put(String.valueOf(g.get("awaiting")), ((Number) g.get("n")).intValue());
            else if (!byBand) all = g;
        }
        // the old-portal payments the reconciliation could not match, within the office's scope (the student's programme as it stands)
        Long unmatched = jdbc.sql("""
                SELECT count(*) FROM people.legacy_transfer_payment l
                  LEFT JOIN people.student s ON s.id = l.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE l.status = 'UNMATCHED'
                   AND (CAST(:fac AS text) IS NULL OR coalesce(d.faculty_code, p.faculty_code) = CAST(:fac AS text))
                   AND (CAST(:dept AS text) IS NULL OR p.dept_code = CAST(:dept AS text))
                """).param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).query(Long.class).single();
        Map<String, Object> fee = jdbc.sql("""
                SELECT people.transfer_fee() AS fee, v.previous_fee, v.stated_at AS revised_at, v.stated_office AS revised_office, v.reason AS revised_reason
                  FROM (SELECT 1) one
                  LEFT JOIN LATERAL (SELECT * FROM finance.transfer_fee_revision x
                                      WHERE x.previous_fee IS NOT NULL AND x.previous_fee IS DISTINCT FROM x.fee
                                      ORDER BY x.stated_at DESC LIMIT 1) v ON true
                """).query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", f.session());
        out.put("filters", f.words());
        out.put("scope", scopeMap());
        out.put("fee", fee.get("fee"));
        out.put("previousFee", fee.get("previous_fee"));
        out.put("revisedAt", fee.get("revised_at"));
        out.put("revisedOffice", fee.get("revised_office"));
        out.put("revisedReason", fee.get("revised_reason"));
        out.put("total", all.getOrDefault("n", 0));
        out.put("applications", all.getOrDefault("applications", 0));
        out.put("bands", bands);
        out.put("awaiting", awaiting);
        out.put("outstanding", all.getOrDefault("outstanding", 0));
        out.put("stillOwing", all.getOrDefault("still_owing", 0));
        out.put("notPaid", all.getOrDefault("not_paid", 0));
        out.put("collectedPortal", all.getOrDefault("collected_portal", 0));
        out.put("collectedOldPortal", all.getOrDefault("collected_old_portal", 0));
        out.put("excess", all.getOrDefault("excess", 0));
        out.put("readyForFinalApproval", all.getOrDefault("ready_final", 0));
        out.put("awaitingApplication", all.getOrDefault("awaiting_application", 0));
        out.put("unmatchedPayments", unmatched);
        return out;
    }

    /** what the filter bar offers: the sessions with applications, the faculties and departments within the office's scope, the
     *  bands and the stages */
    @GetMapping("/options")
    @PreAuthorize(VIEWERS)
    @Transactional(readOnly = true)
    Map<String, Object> options() {
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("current", jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null));
        out.put("sessions", jdbc.sql("SELECT DISTINCT t.session FROM people.transfer_application t WHERE t.session IS NOT NULL ORDER BY 1 DESC").query(String.class).list());
        out.put("faculties", jdbc.sql("""
                SELECT f.code, f.name FROM ref.faculty f WHERE CAST(:fac AS text) IS NULL OR f.code = CAST(:fac AS text) ORDER BY f.name
                """).param("fac", b.fac(), Types.VARCHAR).query().listOfRows());
        out.put("departments", jdbc.sql("""
                SELECT d.code, d.name, d.faculty_code FROM ref.department d
                 WHERE (CAST(:fac AS text) IS NULL OR d.faculty_code = CAST(:fac AS text)) AND (CAST(:dept AS text) IS NULL OR d.code = CAST(:dept AS text))
                 ORDER BY d.name
                """).param("fac", b.fac(), Types.VARCHAR).param("dept", b.dept(), Types.VARCHAR).query().listOfRows());
        out.put("bands", BANDS);
        out.put("awaiting", AWAITING);
        out.put("scope", scopeMap());
        return out;
    }

    record ExportIn(@NotBlank @Pattern(regexp = "XLSX|PDF") String format, String session, String band, String awaiting, String faculty, String dept,
                    @Size(max = 80) String search) {
    }

    /** every application the filters select, names A–Z, for the Excel and PDF engine — and the download recorded on the audit spine:
     *  who, when, the session, the format, the filters and the number of rows */
    @PostMapping("/export")
    @PreAuthorize(VIEWERS)
    @Transactional
    Map<String, Object> export(@Valid @RequestBody ExportIn body) {
        Filters f = filters(body.session(), body.band(), body.awaiting(), body.faculty(), body.dept(), body.search());
        List<Map<String, Object>> rows = bind(jdbc.sql(ROWS + "SELECT " + COLUMNS + " FROM r" + SCOPE + BAND_AND_AWAITING
                + " ORDER BY r.name, r.applied_at, r.application_id"), f).query().listOfRows();
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("""
                INSERT INTO admissions.report_export (report, session, format, filters, row_count, exported_by, office)
                VALUES (:r, :s, :fmt,
                        jsonb_strip_nulls(jsonb_build_object('session', CAST(:sw AS text), 'band', CAST(:band AS text), 'awaiting', CAST(:aw AS text),
                            'faculty', CAST(:fac AS text), 'department', CAST(:dept AS text), 'search', CAST(:search AS text))),
                        :n, :by, (SELECT o.code FROM ref.office o WHERE o.code = CAST(:office AS text)))
                """).param("r", REPORT).param("s", f.session(), Types.VARCHAR).param("fmt", body.format())
                .param("sw", f.session() == null ? "ALL" : f.session()).param("band", f.band() == null ? "ALL" : f.band())
                .param("aw", f.awaiting() == null ? "ALL" : f.awaiting()).param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR)
                .param("search", f.search(), Types.VARCHAR).param("n", rows.size()).param("by", ctx.actorId())
                .param("office", ctx.actorOffice(), Types.VARCHAR).update();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", f.session());
        out.put("format", body.format());
        out.put("filters", f.words());
        out.put("labels", labels(f));
        out.put("scope", scopeMap());
        out.put("generatedBy", jdbc.sql("SELECT nullif(btrim(coalesce(surname, '') || ', ' || coalesce(given_names, '')), ',') FROM iam.person WHERE id = :p")
                .param("p", ctx.actorId()).query(String.class).optional().orElse(null));
        out.put("total", rows.size());
        out.put("rows", rows);
        return out;
    }

    /** the faculty and department of the filters by name, for the heading of a download */
    private Map<String, Object> labels(Filters f) {
        Map<String, Object> m = new LinkedHashMap<>();
        if (f.fac() != null) m.put("faculty", jdbc.sql("SELECT name FROM ref.faculty WHERE code = :c").param("c", f.fac()).query(String.class).optional().orElse(f.fac()));
        if (f.dept() != null) m.put("department", jdbc.sql("SELECT name FROM ref.department WHERE code = :c").param("c", f.dept()).query(String.class).optional().orElse(f.dept()));
        return m;
    }

    private Map<String, Object> scopeMap() {
        OfficeScope.Bound b = scope.bound(null, null, null);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("faculty", b.fac());
        m.put("department", b.dept());
        return m;
    }
}
