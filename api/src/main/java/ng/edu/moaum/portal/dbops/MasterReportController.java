package ng.edu.moaum.portal.dbops;

import java.io.IOException;
import java.io.InputStream;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import javax.sql.DataSource;

import jakarta.servlet.http.HttpServletResponse;
import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.FileObjects;
import ng.edu.moaum.portal.shared.OfficeScope;
import ng.edu.moaum.portal.shared.XlsxStream;

import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowCallbackHandler;
import org.springframework.jdbc.core.namedparam.MapSqlParameterSource;
import org.springframework.jdbc.core.namedparam.NamedParameterJdbcTemplate;
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
 * V650: the Master University Report, under /api/v1/reports/master. One dataset for a session and semester
 * (reporting.master_rows: every student of the scope with the classification, the school-fee position, the registration, GST and
 * EPS owed, registered and paid, the examination card's rule and issue, the GST &amp; EPS permit generated and printed), its summary
 * in one pass (reporting.master_summary), the transactions of the period (reporting.master_payments), and the report's sections
 * (MasterSections) — the same sections for the dashboard (/summary), the PDF (/package: every section, the lists to a cap) and the
 * Excel (/workbook: every section, every row, streamed from the database into the workbook). Every request is held to the acting
 * office's scope on the server (OfficeScope.bound: a Dean's faculty, a Head's department, the College's faculties, a Database
 * Operator's grant); amounts are read only by the offices that read them; the GST and EPS offices read the GST and EPS money and
 * no school-fee amounts; an office that reads no money reads no transactions. The report's reference (RPT/YYYY/NNNNNN) and history
 * are on the official report register; every export is on the query log.
 */
@RestController
@RequestMapping("/api/v1/reports/master")
class MasterReportController {

    /** who reads the master report: examination readiness's readers, the GST and EPS offices, the College's Finance Controller,
     *  Internal Audit */
    static final String READERS = "hasAnyAuthority('OFFICE_dbops','OFFICE_ict','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_records','OFFICE_exams','OFFICE_facultyexams','OFFICE_dean','OFFICE_facultyofficer','OFFICE_hod','OFFICE_bursar',"
            + "'OFFICE_studentaccounts','OFFICE_vc','OFFICE_dvc','OFFICE_admin','OFFICE_super','OFFICE_gst','OFFICE_eps',"
            + "'OFFICE_financecontroller','OFFICE_audit','OFFICE_deputyaudit')";
    /** every amount (school fees, GST, EPS, transactions): the student record's fee readers and the Bursary, the College's Finance
     *  Controller (its College), Internal Audit */
    static final Set<String> MONEY = Set.of("dbops", "ict", "academic", "registrar", "dregistrar", "records", "dean", "facultyofficer", "hod",
            "bursar", "studentaccounts", "vc", "dvc", "admin", "super", "provost", "audit", "deputyaudit", "financecontroller");
    /** the GST and EPS offices: their own money (the GST and EPS fees and payments), no school-fee amounts */
    static final Set<String> GST_MONEY = Set.of("gst", "eps");
    static final Set<String> FEE = Set.of("PAID", "PART_PAID", "NOT_PAID", "NO_FEE_STATED", "ANY_PAYMENT");
    static final Set<String> REG = Set.of("REGISTERED", "NOT_REGISTERED", "PAID_NOT_REGISTERED", "CARRYOVER");
    static final Set<String> GST = Set.of("PAID", "NOT_PAID", "REGISTERED", "NOT_REGISTERED", "APPLICABLE");
    static final Set<String> CARD = Set.of("ELIGIBLE", "NOT_ELIGIBLE", "ISSUED", "NOT_ISSUED");
    static final Set<String> PERMIT = Set.of("ELIGIBLE", "GENERATED", "PRINTED", "NOT_PRINTED");
    static final Set<String> PSTATUS = Set.of("SUCCESSFUL", "PENDING", "FAILED", "REVERSED", "REFUNDED");
    static final Map<String, String> SORTS = Map.of(
            "name", "r.surname, r.other_names, r.matric_no",
            "programme", "r.faculty, r.department, r.programme, r.level, r.surname, r.other_names",
            "level", "r.level, r.surname, r.other_names",
            "outstanding", "r.outstanding DESC NULLS LAST, r.surname, r.other_names");
    /** a list in the PDF: at most this many rows (the workbook carries every row) */
    static final int PDF_CAP = 2500;
    /** where each list sits among the sections */
    static final Map<String, List<String>> AFTER = Map.of(
            "fees_faculty", List.of("fee_details"),
            "tx_faculty", List.of("transactions"),
            "gst", List.of("gst_courses", "gst_payments"),
            "eps", List.of("eps_courses", "eps_payments"),
            "cards", List.of("card_details"),
            "permits", List.of("permit_details"));

    public record IssueIn(@NotBlank @Size(max = 300) String title, Map<String, Object> filters, Map<String, Object> figures, Integer rows,
                          List<String> sections) {
    }

    public record FinishIn(@NotBlank @Size(max = 40) String reference, @NotBlank @Size(max = 12) String status, List<String> formats, Integer rows) {
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    private final JdbcClient jdbc;
    private final Operations ops;
    private final FileObjects files;
    private final NamedParameterJdbcTemplate streaming;

    MasterReportController(JdbcClient jdbc, Operations ops, FileObjects files, DataSource dataSource) {
        this.jdbc = jdbc;
        this.ops = ops;
        this.files = files;
        // the lists are read a few thousand rows at a time, on the transaction's own connection, never all at once
        JdbcTemplate t = new JdbcTemplate(dataSource);
        t.setFetchSize(2000);
        this.streaming = new NamedParameterJdbcTemplate(t);
    }

    /** what the acting office reads of the money: ALL, GST (the GST and EPS fees only) or NONE */
    static String money() {
        String o = Operations.office();
        return MONEY.contains(o) ? "ALL" : GST_MONEY.contains(o) ? "GST" : "NONE";
    }

    private static String up(String v, Set<String> allowed) {
        if (v == null || v.isBlank()) return null;
        String u = v.trim().toUpperCase();
        return allowed.contains(u) ? u : null;
    }

    private static String word(String v) {
        if (v == null || v.isBlank()) return null;
        String u = v.trim().toUpperCase();
        return u.matches("[A-Z0-9_ ]{1,40}") ? u : null;
    }

    private static Integer integer(String v, int min, int max) {
        if (v == null || !v.trim().matches("[0-9]{1,4}")) return null;
        int n = Integer.parseInt(v.trim());
        return n >= min && n <= max ? n : null;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> jsonMap(String text) {
        return text == null ? Map.of() : JSON.readValue(text, Map.class);
    }

    /** the request's filters, the faculty, department and programme held to the office's scope on the server */
    record F(String session, int semester, OfficeScope.Bound bound, Map<String, Object> json, LocalDate from, LocalDate to) {
    }

    private F filters(Map<String, String> q) {
        Map<String, Object> period = jdbc.sql("SELECT session, semester FROM reporting.readiness_period()").query().singleRow();
        String session = q.get("session");
        String s = session != null && session.matches("[0-9]{4}/[0-9]{4}") ? session : (String) period.get("session");
        if (s == null) {
            throw new DomainRuleViolation("MASTER_SESSION", "No session is current; choose the session the report is for.",
                    new DomainRuleViolation.Remedy("Pick the session in the bar.", "You"));
        }
        Integer semester = integer(q.get("semester"), 1, 3);
        int sem = semester != null ? semester : ((Number) period.get("semester")).intValue();
        OfficeScope.Bound b = ops.bound(q.get("fac"), q.get("dept"), q.get("prog"));
        LocalDate d1 = q.get("from") == null || q.get("from").isBlank() ? null : LocalDate.parse(q.get("from").trim());
        LocalDate d2 = q.get("to") == null || q.get("to").isBlank() ? null : LocalDate.parse(q.get("to").trim());
        if (d1 != null && d2 != null && d2.isBefore(d1)) {
            throw new DomainRuleViolation("MASTER_DATES", "The period ends before it starts.", new DomainRuleViolation.Remedy("Choose the dates again.", "You"));
        }
        Map<String, Object> j = new LinkedHashMap<>();
        j.put("fac", b.fac());
        j.put("dept", b.dept());
        j.put("prog", b.prog());
        j.put("level", integer(q.get("level"), 100, 900));
        j.put("type", word(q.get("type")));
        String sx = q.get("sex") == null ? null : q.get("sex").trim().toUpperCase();
        j.put("sex", "M".equals(sx) || "F".equals(sx) || "U".equals(sx) ? sx : null);
        j.put("astatus", word(q.get("astatus")));
        j.put("route", word(q.get("route")));
        j.put("mode", word(q.get("mode")));
        j.put("centre", word(q.get("centre")));
        j.put("fee", up(q.get("fee"), FEE));
        j.put("reg", up(q.get("reg"), REG));
        j.put("gst", up(q.get("gst"), GST));
        j.put("eps", up(q.get("eps"), GST));
        j.put("card", up(q.get("card"), CARD));
        j.put("permit", up(q.get("permit"), PERMIT));
        j.put("purpose", word(q.get("purpose")));
        j.put("status", up(q.get("pstatus"), PSTATUS));
        String ch = q.get("channel");
        j.put("channel", ch == null || ch.isBlank() ? null : ch.trim().replaceAll("[%_]", "").substring(0, Math.min(40, ch.trim().replaceAll("[%_]", "").length())));
        Integer paySem = integer(q.get("paySemester"), 1, 3);
        if (paySem != null) j.put("semester", paySem);
        j.values().removeIf(java.util.Objects::isNull);
        return new F(s, sem, b, j, d1, d2);
    }

    /** the filters as words for a report's heading and its record */
    private Map<String, Object> words(F f) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("session", f.session());
        m.put("semester", f.semester());
        m.put("scope", ops.words(f.bound()));
        m.putAll(f.json());
        if (f.from() != null) m.put("from", f.from().toString());
        if (f.to() != null) m.put("to", f.to().toString());
        return m;
    }

    /** the report's functions are SQL the planner folds into each statement; a plan made for unknown values cannot drop the "no
     *  faculty, department or programme chosen" branches. Measured on the live-shaped copy over the whole University: the summary
     *  65 s generic against 7 s for the request's own values, the students 72 s against 16 s, the period's payments 15 s against
     *  4 s; a faculty and a programme as fast or faster. Transaction-local. */
    private void plan() {
        jdbc.sql("SELECT set_config('plan_cache_mode', 'force_custom_plan', true)").query().singleRow();
    }

    /** the period a report reads when none is chosen and what there is to choose from */
    @GetMapping("/options")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> options() {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("period", jdbc.sql("SELECT session, semester FROM reporting.readiness_period()").query().singleRow());
        out.put("sessions", jdbc.sql("SELECT name FROM policy.academic_session WHERE state IN ('CURRENT', 'CLOSED') ORDER BY starts_on DESC LIMIT 12")
                .query(String.class).list());
        out.put("bounds", jdbc.sql("""
                SELECT a.name AS session, a.starts_on, (SELECT min(m.lectures_from) FROM policy.semester m WHERE m.session = a.name AND m.number = 1) AS first_from,
                       (SELECT min(m.lectures_from) FROM policy.semester m WHERE m.session = a.name AND m.number = 2) AS second_from
                  FROM policy.academic_session a WHERE a.state IN ('CURRENT', 'CLOSED') ORDER BY a.starts_on DESC LIMIT 12
                """).query().listOfRows());
        out.put("types", jdbc.sql("SELECT code, label FROM finance.programme_type ORDER BY ord, code").query().listOfRows());
        out.put("purposes", jdbc.sql("SELECT code, label FROM finance.payment_purpose WHERE active AND code <> 'GATEWAY_TEST' ORDER BY ord, code").query().listOfRows());
        out.put("channels", jdbc.sql("SELECT DISTINCT channel FROM finance.payment_reference WHERE channel IS NOT NULL ORDER BY 1 LIMIT 40").query(String.class).list());
        out.put("modes", jdbc.sql("SELECT DISTINCT study_mode FROM people.student WHERE study_mode IS NOT NULL ORDER BY 1 LIMIT 20").query(String.class).list());
        out.put("centres", jdbc.sql("SELECT DISTINCT centre_code FROM people.student WHERE centre_code IS NOT NULL ORDER BY 1 LIMIT 60").query(String.class).list());
        OfficeScope.Bound b = ops.bound(null, null, null);
        out.put("scope", Map.of("words", ops.words(b), "faculty", b.fac() == null ? "" : b.fac(), "department", b.dept() == null ? "" : b.dept(),
                "programme", b.prog() == null ? "" : b.prog()));
        out.put("money", money());
        return out;
    }

    /* ── the report, computed once a request ───────────────────────────────────────────────────────────────────────── */

    record Report(F f, String money, List<Map<String, Object>> rows, Map<String, Object> tx, List<Map<String, Object>> reconciliation,
                  List<Map<String, Object>> semesters, List<Map<String, Object>> quality, List<MasterSections.Section> sections) {
    }

    private List<Map<String, Object>> shape(List<Map<String, Object>> rows, String money) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            if (!"ALL".equals(money)) for (String k : List.of("payable", "paid_amount", "outstanding")) m.put(k, null);
            if ("NONE".equals(money)) for (String k : List.of("gst_paid_amount", "gst_outstanding")) m.put(k, null);
            out.add(m);
        }
        return out;
    }

    private Report compute(F f, boolean withSemesters, boolean withQuality) {
        return compute(f, withSemesters, withQuality, false);
    }

    /** paymentsKept: the period's payments are in pg_temp.master_t (materialisePayments), read once for the figures and every list */
    private Report compute(F f, boolean withSemesters, boolean withQuality, boolean paymentsKept) {
        plan();
        String money = money();
        List<Map<String, Object>> rows = shape(jdbc.sql("SELECT * FROM reporting.master_summary(:s, :sem, CAST(:f AS jsonb))")
                .param("s", f.session()).param("sem", f.semester()).param("f", Operations.json(f.json())).query().listOfRows(), money);
        Map<String, Object> tx = "NONE".equals(money) ? null : transactionFigures(f, paymentsKept);
        List<Map<String, Object>> rec = reconcile(rows, tx);
        List<Map<String, Object>> sems = null;
        if (withSemesters) {
            sems = new ArrayList<>();
            for (int sem : jdbc.sql("SELECT number FROM policy.semester WHERE session = :s ORDER BY number").param("s", f.session()).query(Integer.class).list()) {
                List<Map<String, Object>> one = sem == f.semester() ? rows.stream().filter(r -> "ALL".equals(r.get("dim"))).toList()
                        : shape(jdbc.sql("SELECT * FROM reporting.master_summary(:s, :sem, CAST(:f AS jsonb)) WHERE dim = 'ALL'").param("s", f.session())
                                .param("sem", sem).param("f", Operations.json(f.json())).query().listOfRows(), money);
                Map<String, Object> m = new LinkedHashMap<>(one.isEmpty() ? Map.of() : one.get(0));
                m.put("semester", sem);
                sems.add(m);
            }
        }
        List<Map<String, Object>> quality = withQuality
                ? jdbc.sql("SELECT kind, label, area, n FROM reporting.data_quality(CAST(:fac AS text), CAST(:dept AS text), CAST(:prog AS text), CAST(:s AS text), CAST(:sem AS int))")
                        .param("s", f.session()).param("sem", f.semester()).param("fac", f.bound().fac(), Types.VARCHAR)
                        .param("dept", f.bound().dept(), Types.VARCHAR).param("prog", f.bound().prog(), Types.VARCHAR).query().listOfRows()
                : null;
        return new Report(f, money, rows, tx, rec, sems, quality, MasterSections.summary(rows, tx, sems, quality, rec, money));
    }

    private Map<String, Object> head(Report r) {
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("filters", words(r.f()));
        out.put("scope", ops.words(r.f().bound()));
        out.put("money", r.money());
        out.put("at", java.time.Instant.now().toString());
        return out;
    }

    /** the dashboard's figures: the summary by every dimension, the transactions of the period, the reconciliation, the sections */
    @GetMapping("/summary")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> summary(@RequestParam Map<String, String> q) {
        Report r = compute(filters(q), false, false);
        Map<String, Object> out = head(r);
        out.put("summary", r.rows());
        out.put("transactions", r.tx());
        out.put("reconciliation", r.reconciliation());
        out.put("sections", r.sections().stream().map(MasterSections.Section::json).toList());
        return out;
    }

    /** the PDF's package: every section in the report's order, the lists to PDF_CAP rows each (with their whole count) */
    @GetMapping("/package")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> pack(@RequestParam Map<String, String> q) {
        F f = filters(q);
        boolean kept = materialisePayments(f);
        Report r = compute(f, "true".equals(q.get("semesters")), true, kept);
        materialise(f);
        List<Map<String, Object>> sections = new ArrayList<>();
        for (MasterSections.Section s : r.sections()) {
            sections.add(s.json());
            for (String key : AFTER.getOrDefault(s.key(), List.of())) {
                MasterSections.Detail d = detail(key, r);
                if (d == null) continue;
                List<Object[]> rows = new ArrayList<>();
                long[] total = {0};
                streamDetail(key, r, PDF_CAP, row -> {
                    total[0] = row.total;
                    rows.add(d.row(row.values));
                });
                if (rows.isEmpty()) continue;
                Map<String, Object> m = new MasterSections.Section(d.key(), d.title(), d.cols(), rows,
                        total[0] > rows.size() ? "The first " + rows.size() + " of " + total[0] + " rows; the Excel workbook carries every row." : d.note()).json();
                m.put("total", total[0]);
                sections.add(m);
            }
        }
        Map<String, Object> out = head(r);
        out.put("summary", r.rows());
        out.put("transactions", r.tx());
        out.put("reconciliation", r.reconciliation());
        out.put("sections", sections);
        ops.log("EXPORT", "MASTER_REPORT", "Master report — PDF package", words(f), ops.words(f.bound()), null, q.get("reference"), "PDF", null);
        return out;
    }

    /** the Excel: the cover, every section and every list, streamed from the database into the workbook */
    @GetMapping("/workbook")
    @PreAuthorize(READERS)
    @Transactional
    void workbook(@RequestParam Map<String, String> q, HttpServletResponse response) throws IOException {
        F f = filters(q);
        boolean kept = materialisePayments(f);
        Report r = compute(f, "true".equals(q.get("semesters")), true, kept);
        materialise(f);
        String reference = q.get("reference") != null && q.get("reference").matches("RPT/[0-9]{4}/[0-9]{6}") ? q.get("reference") : null;
        String who = jdbc.sql("SELECT helpdesk.person_name(nullif(current_setting('moaum.actor_id', true), '')::uuid)").query(String.class).optional().orElse("");
        String school = ng.edu.moaum.portal.platform.Branding.name().toUpperCase();
        String title = "Master Academic, Finance & Student Report";
        String facts = f.session() + " · " + MasterSections.sem(f.semester()) + " · " + ops.words(f.bound()) + (reference == null ? "" : " · Reference " + reference)
                + " · Generated " + java.time.ZonedDateTime.now(java.time.ZoneId.of("Africa/Lagos")).format(java.time.format.DateTimeFormatter.ofPattern("d MMM yyyy HH:mm"))
                + (who.isBlank() ? "" : " by " + who);
        response.setContentType("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet");
        response.setHeader("Content-Disposition", "attachment; filename=\"master-report-" + (reference == null ? f.session().replace('/', '-') : reference.replace('/', '-')) + ".xlsx\"");
        long[] rowsWritten = {0};
        try (XlsxStream x = new XlsxStream(response.getOutputStream(), crest())) {
            // the cover: the report's facts, then the filters
            XlsxStream.Sheet cover = x.sheet("Cover & Summary", school, title.toUpperCase(), facts,
                    List.of(XlsxStream.Col.text("Item", 30), XlsxStream.Col.text("Value", 70)));
            cover.row("Academic session", f.session());
            cover.row("Semester", MasterSections.sem(f.semester()));
            cover.row("Scope", ops.words(f.bound()));
            cover.row("Report period", f.from() == null && f.to() == null ? "The whole session" : (f.from() == null ? "the start" : f.from()) + " to " + (f.to() == null ? "today" : f.to()));
            cover.row("Generated by", who);
            cover.row("Report reference", reference == null ? "" : reference);
            for (Map.Entry<String, Object> e : f.json().entrySet()) {
                if (List.of("fac", "dept", "prog").contains(e.getKey())) continue;
                cover.row("Filter: " + e.getKey(), String.valueOf(e.getValue()));
            }
            for (MasterSections.Section s : r.sections()) {
                XlsxStream.Sheet sh = x.sheet(s.title(), school, s.title() + " — " + title, facts, s.cols());
                for (Object[] row : s.rows()) sh.row(row);
                rowsWritten[0] += sh.count();
                for (String key : AFTER.getOrDefault(s.key(), List.of())) {
                    MasterSections.Detail d = detail(key, r);
                    if (d == null) continue;
                    XlsxStream.Sheet ds = x.sheet(d.title(), school, d.title() + " — " + title, facts, d.cols());
                    streamDetail(key, r, Integer.MAX_VALUE, row -> {
                        try {
                            ds.row(d.row(row.values));
                        } catch (IOException e) {
                            throw new java.io.UncheckedIOException(e);
                        }
                    });
                    rowsWritten[0] += ds.count();
                }
            }
        }
        ops.log("EXPORT", "MASTER_REPORT", "Master report — Excel", words(f), ops.words(f.bound()), (int) Math.min(Integer.MAX_VALUE, rowsWritten[0]), reference, "XLSX", null);
    }

    /** the crest every sheet carries: the Institution Profile's logo where it is a PNG, else the portal's own */
    private byte[] crest() {
        try {
            UUID id = jdbc.sql("SELECT logo_object_id FROM platform.institution_profile WHERE id").query(UUID.class).optional().orElse(null);
            if (id != null) {
                FileObjects.Typed t = files.typed(id);
                if (t != null && t.bytes() != null && "image/png".equalsIgnoreCase(t.contentType())) return t.bytes();
            }
        } catch (RuntimeException unreadable) {
            // the portal's own crest below
        }
        try (InputStream in = MasterReportController.class.getResourceAsStream("/branding/crest.png")) {
            return in == null ? null : in.readAllBytes();
        } catch (IOException e) {
            return null;
        }
    }

    /** the students of the request, once, for every list drawn from them */
    private void materialise(F f) {
        jdbc.sql("DROP TABLE IF EXISTS pg_temp.master_m").update();
        jdbc.sql("CREATE TEMP TABLE master_m ON COMMIT DROP AS SELECT * FROM reporting.master_rows(:s, :sem, CAST(:f AS jsonb))")
                .param("s", f.session()).param("sem", f.semester()).param("f", Operations.json(f.json())).update();
    }

    private MasterSections.Detail detail(String key, Report r) {
        String money = r.money();
        String session = r.f().session();
        int semester = r.f().semester();
        return switch (key) {
            case "fee_details" -> MasterSections.fees(money, session, semester);
            case "card_details" -> MasterSections.cards(session, semester);
            case "permit_details" -> MasterSections.permits(session, semester);
            case "gst_courses" -> MasterSections.courses("GST", session, semester);
            case "eps_courses" -> MasterSections.courses("EPS", session, semester);
            case "transactions" -> "NONE".equals(money) ? null : MasterSections.transactions("transactions", "Payment transactions");
            case "gst_payments" -> "NONE".equals(money) ? null : MasterSections.transactions("gst_payments", "GST payments");
            case "eps_payments" -> "NONE".equals(money) ? null : MasterSections.transactions("eps_payments", "EPS payments");
            default -> null;
        };
    }

    private record Streamed(Map<String, Object> values, long total) {
    }

    /** a list's rows from the database, a few thousand at a time — the students from the request's own table, the transactions
     *  newest first, the people A to Z */
    private void streamDetail(String key, Report r, int cap, java.util.function.Consumer<Streamed> each) {
        String sql;
        MapSqlParameterSource p = new MapSqlParameterSource().addValue("cap", cap);
        F f = r.f();
        switch (key) {
            case "fee_details" -> sql = "SELECT m.*, count(*) OVER () AS total_rows FROM pg_temp.master_m m ORDER BY m.surname, m.other_names, m.matric_no LIMIT :cap";
            case "card_details" -> sql = "SELECT m.*, count(*) OVER () AS total_rows FROM pg_temp.master_m m ORDER BY m.surname, m.other_names, m.matric_no LIMIT :cap";
            case "permit_details" -> sql = """
                    SELECT m.*, count(*) OVER () AS total_rows FROM pg_temp.master_m m
                     WHERE m.permit_eligible OR m.permit_generated OR m.gst_registered OR m.eps_registered
                     ORDER BY m.surname, m.other_names, m.matric_no LIMIT :cap""";
            case "gst_courses", "eps_courses" -> {
                sql = """
                        SELECT m.matric_no, m.jamb_no, m.surname, m.other_names, m.sex, m.faculty, m.department, m.programme, m.level,
                               e.course_code, e.title, e.units, e.registered, CASE WHEN :o = 'GST' THEN m.gst_status ELSE m.eps_status END AS payment_status,
                               m.gst_reference AS payment_reference, count(*) OVER () AS total_rows
                          FROM pg_temp.master_m m
                          JOIN pg_temp.master_g e ON e.student_id = m.student_id AND e.office = :o AND (e.counts OR e.registered)
                         ORDER BY m.surname, m.other_names, m.matric_no, e.course_code LIMIT :cap""";
                p.addValue("o", "gst_courses".equals(key) ? "GST" : "EPS");
                // the session's GST and EPS rows, read once for both lists
                jdbc.sql("CREATE TEMP TABLE IF NOT EXISTS master_g ON COMMIT DROP AS SELECT * FROM finance.gst_eps_rows_all(:s)").param("s", f.session()).update();
            }
            default -> {
                // the transactions: the period's, the GST or the EPS fee's
                Object pin = f.json().get("purposeIn");
                String only = "gst_payments".equals(key) ? "GST_FEE" : "eps_payments".equals(key) ? "EPS_FEE" : null;
                sql = """
                        SELECT t.*, count(*) OVER () AS total_rows
                          FROM pg_temp.master_t t
                         WHERE (CAST(:pin AS text[]) IS NULL OR t.purpose_code = ANY (CAST(:pin AS text[])))
                           AND (CAST(:only AS text) IS NULL OR t.purpose_code = :only)
                         ORDER BY coalesce(t.confirmed_at, t.generated_at) DESC, t.reference LIMIT :cap""";
                p.addValue("s", f.session()).addValue("d1", f.from() == null ? null : java.sql.Date.valueOf(f.from()), Types.DATE)
                        .addValue("d2", f.to() == null ? null : java.sql.Date.valueOf(f.to()), Types.DATE).addValue("f", Operations.json(f.json()))
                        .addValue("pin", pin == null ? null : "{" + String.join(",", ((List<?>) pin).stream().map(String::valueOf).toList()) + "}", Types.VARCHAR)
                        .addValue("only", only, Types.VARCHAR);
            }
        }
        streaming.query(sql, p, (RowCallbackHandler) rs -> {
            java.sql.ResultSetMetaData md = rs.getMetaData();
            Map<String, Object> row = new LinkedHashMap<>();
            for (int i = 1; i <= md.getColumnCount(); i++) row.put(md.getColumnLabel(i), rs.getObject(i));
            each.accept(new Streamed(row, ((Number) row.get("total_rows")).longValue()));
        });
    }

    /* ── the transactions' figures and the reconciliation ───────────────────────────────────────────────────────────── */

    private static final String PAYMENTS = paymentsFrom(false);

    /** the period's payments: read now, or from the request's own table (pg_temp.master_t) when the package or workbook made it */
    private static String paymentsFrom(boolean kept) {
        return (kept ? "FROM pg_temp.master_t t\n"
                     : "FROM reporting.master_payments(CAST(:s AS text), CAST(:d1 AS date), CAST(:d2 AS date), CAST(:f AS jsonb)) t\n")
                + "WHERE (CAST(:pin AS text[]) IS NULL OR t.purpose_code = ANY (CAST(:pin AS text[])))\n";
    }

    /** the period's payments read once into the request's table, for the figures and the three lists; false where the office reads no
     *  money (nothing is listed then) */
    private boolean materialisePayments(F f) {
        if ("NONE".equals(money())) return false;
        plan();
        jdbc.sql("DROP TABLE IF EXISTS pg_temp.master_t").update();
        jdbc.sql("CREATE TEMP TABLE master_t ON COMMIT DROP AS SELECT * FROM reporting.master_payments(CAST(:s AS text), CAST(:d1 AS date), CAST(:d2 AS date), CAST(:f AS jsonb))")
                .param("s", f.session()).param("d1", f.from(), Types.DATE).param("d2", f.to(), Types.DATE).param("f", Operations.json(f.json())).update();
        return true;
    }

    private JdbcClient.StatementSpec bindPayments(JdbcClient.StatementSpec q, F f) {
        Object pin = f.json().get("purposeIn");
        return q.param("s", f.session()).param("d1", f.from(), Types.DATE).param("d2", f.to(), Types.DATE)
                .param("f", Operations.json(f.json()))
                .param("pin", pin == null ? null : "{" + String.join(",", ((List<?>) pin).stream().map(String::valueOf).toList()) + "}", Types.VARCHAR);
    }

    /** the transactions of the period: totals by status (transactions, unique students, amount, net), by purpose, day, semester, faculty */
    private Map<String, Object> transactionFigures(F f, boolean kept) {
        if ("GST".equals(money()) && f.json().get("purpose") == null) f.json().put("purposeIn", List.of("GST_FEE", "EPS_FEE"));
        String json = bindPayments(jdbc.sql("""
                WITH t AS MATERIALIZED (SELECT t.* """ + paymentsFrom(kept) + """
                )
                SELECT json_build_object(
                  'byStatus', (SELECT coalesce(json_agg(x ORDER BY x.status), '[]') FROM (
                        SELECT t.status, count(*) AS transactions, count(DISTINCT coalesce(t.student_id::text, t.number)) AS students,
                               sum(t.amount) AS amount, sum(t.net_amount) AS net FROM t GROUP BY t.status) x),
                  'byPurpose', (SELECT coalesce(json_agg(x ORDER BY x.revenue DESC, x.label), '[]') FROM (
                        SELECT t.purpose_code AS code, coalesce(max(t.purpose_label), t.purpose_code) AS label, count(*) AS transactions,
                               count(DISTINCT coalesce(t.student_id::text, t.number)) AS students,
                               count(*) FILTER (WHERE t.status = 'SUCCESSFUL') AS successful, count(*) FILTER (WHERE t.status = 'PENDING') AS pending,
                               count(*) FILTER (WHERE t.status = 'FAILED') AS failed, count(*) FILTER (WHERE t.status = 'REVERSED') AS reversed,
                               count(*) FILTER (WHERE t.status = 'REFUNDED') AS refunded,
                               coalesce(sum(t.net_amount) FILTER (WHERE t.status = 'SUCCESSFUL'), 0) AS revenue
                          FROM t GROUP BY t.purpose_code) x),
                  'byDay', (SELECT coalesce(json_agg(x ORDER BY x.day), '[]') FROM (
                        SELECT t.on_day AS day, count(*) FILTER (WHERE t.status = 'SUCCESSFUL') AS transactions,
                               coalesce(sum(t.net_amount) FILTER (WHERE t.status = 'SUCCESSFUL'), 0) AS amount
                          FROM t GROUP BY t.on_day) x),
                  'bySemester', (SELECT coalesce(json_agg(x ORDER BY x.semester NULLS LAST), '[]') FROM (
                        SELECT t.semester, count(*) FILTER (WHERE t.status = 'SUCCESSFUL') AS transactions,
                               coalesce(sum(t.net_amount) FILTER (WHERE t.status = 'SUCCESSFUL'), 0) AS amount
                          FROM t GROUP BY t.semester) x),
                  'byFaculty', (SELECT coalesce(json_agg(x ORDER BY x.faculty NULLS LAST), '[]') FROM (
                        SELECT t.faculty_code, t.faculty,
                               coalesce(sum(t.net_amount) FILTER (WHERE t.status = 'SUCCESSFUL' AND t.purpose_code = 'SCHOOL_FEES'), 0) AS school_fees,
                               coalesce(sum(t.net_amount) FILTER (WHERE t.status = 'SUCCESSFUL'), 0) AS revenue
                          FROM t GROUP BY t.faculty_code, t.faculty) x),
                  'total', (SELECT json_build_object('transactions', count(*), 'students', count(DISTINCT coalesce(t.student_id::text, t.number)),
                                   'revenue', coalesce(sum(t.net_amount) FILTER (WHERE t.status = 'SUCCESSFUL'), 0),
                                   'refunded', coalesce(sum(t.refunded), 0)) FROM t)
                )::text
                """), f).query(String.class).single();
        return jsonMap(json);
    }

    /** the summary checked against itself: each faculty the sum of its departments, each department of its programmes, each programme
     *  of its levels, the levels and the faculties the University, the genders and the fee standings the whole; the revenue by
     *  purpose the period's revenue */
    @SuppressWarnings("unchecked")
    private static List<Map<String, Object>> reconcile(List<Map<String, Object>> rows, Map<String, Object> tx) {
        List<Map<String, Object>> out = new ArrayList<>();
        Map<String, Object> all = rows.stream().filter(r -> "ALL".equals(r.get("dim"))).findFirst().orElse(null);
        if (all == null) return out;
        long total = MasterSections.n(all.get("total"));
        out.add(check("Faculty totals equal the scope's total", sum(rows, "FACULTY"), total));
        out.add(check("Level totals equal the scope's total", sum(rows, "LEVEL"), total));
        out.add(check("Male + female + not stated equals the total", MasterSections.n(all.get("male")) + MasterSections.n(all.get("female"))
                + MasterSections.n(all.get("sex_unknown")), total));
        out.add(check("Paid in full + part paid + not paid + no fee stated equals the total", MasterSections.n(all.get("fees_paid")) + MasterSections.n(all.get("fees_part"))
                + MasterSections.n(all.get("fees_not_paid")) + MasterSections.n(all.get("no_fee")), total));
        boolean facOk = true, deptOk = true, progOk = true;
        for (Map<String, Object> r : rows) {
            if ("FACULTY".equals(r.get("dim")) && sumOf(rows, "DEPARTMENT", r, "faculty_code") != MasterSections.n(r.get("total"))) facOk = false;
            if ("DEPARTMENT".equals(r.get("dim")) && sumOf(rows, "PROGRAMME", r, "faculty_code", "dept_code") != MasterSections.n(r.get("total"))) deptOk = false;
            if ("PROGRAMME".equals(r.get("dim")) && sumOf(rows, "PROGRAMME_LEVEL", r, "faculty_code", "dept_code", "programme_code") != MasterSections.n(r.get("total"))) progOk = false;
        }
        out.add(holds("Each faculty equals the sum of its departments", facOk));
        out.add(holds("Each department equals the sum of its programmes", deptOk));
        out.add(holds("Each programme equals the sum of its levels", progOk));
        if (tx != null && tx.get("byPurpose") instanceof List<?> purposes && tx.get("total") instanceof Map<?, ?> tt) {
            double byPurpose = 0;
            for (Object p : purposes) byPurpose += ((Number) ((Map<String, Object>) p).get("revenue")).doubleValue();
            double revenue = ((Number) tt.get("revenue")).doubleValue();
            Map<String, Object> c = new LinkedHashMap<>();
            c.put("check", "Revenue by payment purpose equals the period's revenue (successful payments, net of refunds)");
            c.put("holds", Math.abs(byPurpose - revenue) < 0.005);
            c.put("left", byPurpose);
            c.put("right", revenue);
            out.add(c);
            long byStatus = 0;
            if (tx.get("byStatus") instanceof List<?> statuses) for (Object st : statuses) byStatus += MasterSections.n(((Map<String, Object>) st).get("transactions"));
            out.add(check("Transactions by status equal the period's transactions", byStatus, MasterSections.n(tt.get("transactions"))));
        }
        return out;
    }

    private static Map<String, Object> check(String what, long left, long right) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("check", what);
        m.put("holds", left == right);
        m.put("left", left);
        m.put("right", right);
        return m;
    }

    private static Map<String, Object> holds(String what, boolean ok) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("check", what);
        m.put("holds", ok);
        return m;
    }

    private static long sum(List<Map<String, Object>> rows, String dim) {
        return rows.stream().filter(r -> dim.equals(r.get("dim"))).mapToLong(r -> MasterSections.n(r.get("total"))).sum();
    }

    private static long sumOf(List<Map<String, Object>> rows, String dim, Map<String, Object> parent, String... keys) {
        return rows.stream().filter(r -> dim.equals(r.get("dim")) && java.util.Arrays.stream(keys).allMatch(k -> java.util.Objects.equals(r.get(k), parent.get(k))))
                .mapToLong(r -> MasterSections.n(r.get("total"))).sum();
    }

    /* ── the lists behind the figures ─────────────────────────────────────────────────────────────────────────────── */

    /** the students behind a figure — the same dataset, narrowed by the figure's own filters; a page of them */
    @GetMapping("/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam Map<String, String> q) {
        F f = filters(q);
        plan();
        Integer size = integer(q.get("size"), 1, 500);
        Integer page = integer(q.get("page"), 1, 9999);
        int sz = size == null ? 50 : size;
        int pg = page == null ? 1 : page;
        String order = SORTS.getOrDefault(q.getOrDefault("sort", "programme"), SORTS.get("programme"));
        List<Map<String, Object>> rows = jdbc.sql("SELECT r.*, count(*) OVER () AS total FROM reporting.master_rows(:s, :sem, CAST(:f AS jsonb)) r ORDER BY "
                        + order + " LIMIT :lim OFFSET :off")
                .param("s", f.session()).param("sem", f.semester()).param("f", Operations.json(f.json())).param("lim", sz).param("off", (pg - 1) * sz)
                .query().listOfRows();
        String money = money();
        List<Map<String, Object>> shaped = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.remove("total");
            if (!"ALL".equals(money)) for (String k : List.of("payable", "paid_amount", "outstanding")) m.put(k, null);
            if ("NONE".equals(money)) for (String k : List.of("gst_fee", "gst_paid_amount", "gst_outstanding")) m.put(k, null);
            shaped.add(m);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.isEmpty() ? 0 : MasterSections.n(rows.get(0).get("total")));
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", shaped);
        out.put("filters", words(f));
        return out;
    }

    /** the transactions of the period, newest first, a page of them */
    @GetMapping("/transactions")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> transactions(@RequestParam Map<String, String> q) {
        if ("NONE".equals(money())) {
            throw new DomainRuleViolation("MASTER_MONEY", "Your office does not read payment transactions.",
                    new DomainRuleViolation.Remedy("The Bursary's and the fee readers' offices read them.", "Bursary"));
        }
        F f = filters(q);
        if ("GST".equals(money()) && f.json().get("purpose") == null) f.json().put("purposeIn", List.of("GST_FEE", "EPS_FEE"));
        plan();
        Integer size = integer(q.get("size"), 1, 500);
        Integer page = integer(q.get("page"), 1, 9999);
        int sz = size == null ? 50 : size;
        int pg = page == null ? 1 : page;
        List<Map<String, Object>> rows = bindPayments(jdbc.sql("SELECT t.*, count(*) OVER () AS total " + PAYMENTS
                + " ORDER BY coalesce(t.confirmed_at, t.generated_at) DESC, t.reference LIMIT :lim OFFSET :off"), f)
                .param("lim", sz).param("off", (pg - 1) * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", rows.isEmpty() ? 0 : MasterSections.n(rows.get(0).get("total")));
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows.stream().map(r -> { Map<String, Object> m = new LinkedHashMap<>(r); m.remove("total"); return m; }).toList());
        out.put("filters", words(f));
        return out;
    }

    /* ── the report's reference and history ────────────────────────────────────────────────────────────────────────── */

    /** the report's reference: RPT/YYYY/NNNNNN on the official report register, GENERATING until the browser has written it */
    @PostMapping("/issue")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> issue(@Valid @RequestBody IssueIn body) {
        String scope = body.filters() == null ? null : String.valueOf(body.filters().getOrDefault("scope", ""));
        String ref = jdbc.sql("SELECT reporting.issue_report('MASTER', :t, CAST(:f AS jsonb), :sc, CAST(:fig AS jsonb), :n, CAST(:parts AS jsonb))")
                .param("t", body.title().trim()).param("f", Operations.json(body.filters() == null ? Map.of() : body.filters()))
                .param("sc", scope, Types.VARCHAR).param("fig", Operations.json(body.figures()), Types.VARCHAR).param("n", body.rows(), Types.INTEGER)
                .param("parts", Operations.json(body.sections() == null ? List.of() : body.sections()), Types.VARCHAR).query(String.class).single();
        ops.log("ISSUE", "MASTER_REPORT", body.title().trim(), body.filters(), scope, body.rows(), ref, null, null);
        return Map.of("reference", ref, "status", "GENERATING");
    }

    /** the browser has written the PDF and the Excel (or could not) */
    @PostMapping("/finish")
    @PreAuthorize(READERS)
    @Transactional
    Map<String, Object> finish(@Valid @RequestBody FinishIn body) {
        String st = body.status().trim().toUpperCase();
        jdbc.sql("SELECT reporting.finish_report(:r, :s, CAST(:fm AS text[]), :n)").param("r", body.reference().trim()).param("s", st)
                .param("fm", "{" + String.join(",", body.formats() == null ? List.of() : body.formats().stream().map(x -> x.replaceAll("[^A-Za-z]", "")).toList()) + "}")
                .param("n", body.rows(), Types.INTEGER).query().listOfRows();
        return Map.of("reference", body.reference().trim(), "status", st);
    }

    /** the master reports issued: everyone's for the offices that audit the register and the Bursar, one's own for every other office */
    @GetMapping("/history")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> history() {
        boolean everyone = Operations.AUDITORS.contains(Operations.office()) || "bursar".equals(Operations.office());
        return jdbc.sql("""
                SELECT r.reference, r.title, r.filters::text AS filters, r.scope, r.row_count, r.status, r.formats::text AS formats, r.generated_at, r.completed_at,
                       r.actor_office, helpdesk.person_name(r.generated_by) AS generated_by
                  FROM reporting.official_report r
                 WHERE r.kind = 'MASTER' AND (:all OR r.generated_by = nullif(current_setting('moaum.actor_id', true), '')::uuid)
                 ORDER BY r.generated_at DESC LIMIT 200
                """).param("all", everyone).query().listOfRows();
    }
}
