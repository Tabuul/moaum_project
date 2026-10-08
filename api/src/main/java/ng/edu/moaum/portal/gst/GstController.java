package ng.edu.moaum.portal.gst;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.time.OffsetDateTime;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.GstEpsExplain;

/**
 * GST &amp; EPS (V314). The Bursar states the GST fee per session and the rule it enforces; the GST and EPS
 * offices read their dashboards, their students, their courses and their results, and manage their own
 * courses; every figure is counted in the database from finance.gst_population and
 * finance.gst_course_stats, scoped by session, semester, faculty, department, programme, level, gender,
 * course, payment and registration. The GST office sees GST, the EPS office sees EPS; the Bursar and the
 * University's offices see both. Neither office touches the fee: that door is the Bursar's.
 */
@RestController
@RequestMapping("/api/v1/gst")
class GstController {

    private static final String READERS =
            "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_bursar','OFFICE_financecontroller','OFFICE_registrar','OFFICE_dregistrar',"
            + "'OFFICE_dvc','OFFICE_vc','OFFICE_academic','OFFICE_records','OFFICE_ict','OFFICE_admin','OFFICE_super')";
    /** the one office that states the fee and the rule */
    private static final String BURSAR = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** the two offices that manage their own courses */
    private static final String MANAGERS = "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_super')";
    private static final Set<String> OFFICES = Set.of("GST", "EPS");
    private static final Set<String> PAY = Set.of("PAID", "NOT_PAID", "PENDING", "NOT_STATED", "NOT_REQUIRED", "EXEMPT");
    /** V366: who a list holds — the students the office's courses concern (the default), or one kind of them, or those they do not concern */
    private static final Set<String> ELIGIBILITY = Set.of("ALL", "REQUIRED", "CARRYOVER", "COMPLETED", "NOT_APPLICABLE", "REVIEW");
    private static final Set<String> STATUSES = Set.of("ACTIVE", "PROBATION", "ADMITTED");
    private static final Set<String> MODES = Set.of("UTME", "DIRECT_ENTRY", "TRANSFER", "JUPEB", "SANDWICH");

    private final JdbcClient jdbc;

    GstController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /* ── the Bursar's door: the fee and the rule ── */

    public record FeeIn(@NotBlank String session, @NotNull BigDecimal amount, Integer level, @Size(max = 20) String entryMode,
                        @Size(max = 10) String facultyCode, @Size(max = 10) String programmeCode, LocalDate effectiveFrom, @Size(max = 300) String note) {
    }

    public record SettingIn(Boolean requiredForGstEps, Boolean requiredForAll, Boolean coversEps) {
    }

    /** the GST fee of a session: the live rules, the superseded ones, and the rule the payment enforces */
    @GetMapping("/fee")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> fee(@RequestParam(required = false) String session) {
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session ORDER BY name DESC").query().listOfRows());
        out.put("setting", setting());
        out.put("rules", rules(s, false));
        out.put("history", rules(s, true));
        out.put("paid", jdbc.sql("""
                SELECT count(DISTINCT r.student_id) AS students, coalesce(sum(r.amount), 0) AS amount
                  FROM finance.payment_reference r WHERE r.session = :s AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                """).param("s", s).query().singleRow());
        // V366: the Bursary's standing — who owes the fee because a GST/EPS course requires it, and who does not; "not applicable" is never "unpaid"
        out.put("standing", jdbc.sql("""
                SELECT count(*) AS undergraduates,
                       count(*) FILTER (WHERE p.required) AS applicable,
                       count(*) FILTER (WHERE NOT p.required) AS not_applicable,
                       count(*) FILTER (WHERE p.required AND p.pay_state = 'PAID') AS paid,
                       count(*) FILTER (WHERE p.required AND p.pay_state = 'EXEMPT') AS exempt,
                       count(*) FILTER (WHERE p.required AND p.pay_state IN ('NOT_PAID', 'PENDING')) AS owing,
                       count(*) FILTER (WHERE p.required AND p.pay_state = 'NOT_STATED') AS not_stated,
                       count(*) FILTER (WHERE p.review) AS review,
                       coalesce(sum(p.fee - p.paid) FILTER (WHERE p.required AND p.pay_state IN ('NOT_PAID', 'PENDING')), 0) AS outstanding,
                       count(*) FILTER (WHERE p.gst_required) AS gst_required,
                       count(*) FILTER (WHERE p.eps_required) AS eps_required,
                       count(*) FILTER (WHERE p.gst_carryover OR p.eps_carryover) AS carryover
                  FROM finance.gst_population(:s, NULL) p
                """).param("s", s).query().singleRow());
        // V367: GST/EPS courses bound to programmes but not opened this session — their students owe nothing until the office opens them
        out.put("gaps", gaps(s, null));
        return out;
    }

    /**
     * V366: the students who paid the GST fee though no GST/EPS course requires it of them this session — for the Bursary's review.
     * V367: each payment awaiting a decision (rows), and the decisions taken (decided): kept with a note, or a refund raised against
     * the payment through the maker–checker refund workflow, with where that refund stands.
     */
    @GetMapping("/fee/review")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> review(@RequestParam(required = false) String session) {
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("rows", jdbc.sql("""
                SELECT p.student_id, p.number, p.surname, p.other_names, p.programme_code, p.programme, p.department, p.faculty, p.level, p.paid, p.reference, p.paid_at,
                       p.pay_source, p.gst_reason, p.eps_reason,
                       (SELECT coalesce(json_agg(json_build_object('reference', r.reference, 'amount', r.amount - finance.gst_refunded(r.reference), 'paid_at', r.confirmed_at)
                                                 ORDER BY r.confirmed_at)::text, '[]')
                          FROM finance.payment_reference r
                         WHERE r.student_id = p.student_id AND r.session = :s AND r.purpose LIKE 'GST fee %' AND r.confirmed_at IS NOT NULL
                           AND r.amount > finance.gst_refunded(r.reference)
                           AND NOT EXISTS (SELECT 1 FROM finance.gst_payment_review d LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                                            WHERE d.reference = r.reference AND (d.decision = 'KEEP' OR rf.state <> 'REJECTED'))) AS payments
                  FROM finance.gst_population(:s, NULL) p WHERE p.review
                 ORDER BY p.surname, p.other_names LIMIT 2000
                """).param("s", s).query().listOfRows());
        out.put("decided", jdbc.sql("""
                SELECT d.reference, d.decision, d.note, d.decided_at, d.decided_office, st.id AS student_id, coalesce(st.matric_no, st.admission_no) AS number,
                       st.surname, st.other_names, pr.amount AS paid, rf.reference AS refund_reference, rf.state AS refund_state, rf.amount AS refund_amount,
                       (SELECT ps.surname || ', ' || ps.given_names FROM iam.person ps WHERE ps.id = d.decided_by) AS decided_by
                  FROM finance.gst_payment_review d
                  JOIN people.student st ON st.id = d.student_id
                  JOIN finance.payment_reference pr ON pr.reference = d.reference
                  LEFT JOIN finance.refund rf ON rf.id = d.refund_id
                 WHERE d.session = :s
                 ORDER BY d.decided_at DESC LIMIT 2000
                """).param("s", s).query().listOfRows());
        return out;
    }

    public record DecisionIn(@NotBlank @Size(max = 10) String decision, @NotBlank @Size(max = 500) String note, @Size(max = 200) String payer,
                             @Size(max = 120) String bank, @Size(max = 200) String accountName, @Size(max = 4) String accountLast4) {
    }

    /**
     * V367: the Bursary decides a GST payment no course requires — KEEP with its reason, or REFUND, which raises a refund of it
     * through the refunds desk's maker–checker workflow (another officer approves; nothing is approved or paid here). The
     * payment itself is never changed.
     */
    @PostMapping("/fee/review/{reference}")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> decide(@PathVariable String reference, @Valid @RequestBody DecisionIn body) {
        Map<String, Object> d = jdbc.sql("SELECT d.* FROM finance.decide_gst_payment(:r, :d, :n, :p, :b, :an, :l) d")
                .param("r", reference.trim()).param("d", body.decision().trim().toUpperCase()).param("n", body.note().trim())
                .param("p", blank(body.payer()), Types.VARCHAR).param("b", blank(body.bank()), Types.VARCHAR)
                .param("an", blank(body.accountName()), Types.VARCHAR).param("l", blank(body.accountLast4()), Types.VARCHAR)
                .query().singleRow();
        Map<String, Object> out = new LinkedHashMap<>(d);
        if (d.get("refund_id") != null) {
            out.put("refund", jdbc.sql("SELECT reference, state, amount FROM finance.refund WHERE id = :id").param("id", d.get("refund_id")).query().singleRow());
        }
        return out;
    }

    /** the Bursar states the GST fee for a session, for everyone or for a level, an entry mode, a faculty or a programme; the old rule is superseded, never edited */
    @PutMapping("/fee")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> stateFee(@Valid @RequestBody FeeIn body) {
        if (body.amount().signum() < 0) {
            throw new DomainRuleViolation("GST_FEE_AMOUNT", "The GST fee is an amount of zero or more.", new DomainRuleViolation.Remedy("State the fee in naira.", "Bursary"));
        }
        String mode = blank(body.entryMode()) == null ? null : body.entryMode().trim().toUpperCase().replace(' ', '_');
        if (mode != null && !MODES.contains(mode)) {
            throw new DomainRuleViolation("GST_FEE_ENTRY_MODE", "An entry mode is UTME, Direct Entry, Transfer, JUPEB or Sandwich, or blank for all.", new DomainRuleViolation.Remedy("Choose one or leave it blank.", "Bursary"));
        }
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT finance.state_gst_fee(:s, :a, :l, :m, :f, :p, :d, :n, :by, :office)")
                .param("s", body.session().trim()).param("a", body.amount()).param("l", body.level(), Types.INTEGER).param("m", mode, Types.VARCHAR)
                .param("f", blank(body.facultyCode()), Types.VARCHAR).param("p", blank(body.programmeCode()), Types.VARCHAR)
                .param("d", body.effectiveFrom(), Types.DATE).param("n", blank(body.note()), Types.VARCHAR)
                .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).query(UUID.class).single();
        return fee(body.session().trim());
    }

    /** a live rule withdrawn: students it priced fall back to the next rule, or to no fee */
    @PostMapping("/fee/{id}/end")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> endFee(@PathVariable UUID id, @RequestParam(required = false) String session) {
        jdbc.sql("SELECT finance.end_gst_fee(:id)").param("id", id).query().listOfRows();
        return fee(session);
    }

    /** the rule: what the GST payment gates, and that it covers EPS */
    @PutMapping("/setting")
    @PreAuthorize(BURSAR)
    @Transactional
    Map<String, Object> setting(@RequestBody SettingIn body, @RequestParam(required = false) String session) {
        AuditContext ctx = AuditContextHolder.required();
        jdbc.sql("SELECT finance.set_gst_setting(:a, :b, :c, :by, :office)")
                .param("a", body.requiredForGstEps(), Types.BOOLEAN).param("b", body.requiredForAll(), Types.BOOLEAN).param("c", body.coversEps(), Types.BOOLEAN)
                .param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR).query().listOfRows();
        return fee(session);
    }

    /* ── the offices' desks ── */

    /** the filters every figure is held to; a filter outside the office's own category is simply empty */
    record Filters(String office, String session, Integer semester, String fac, String dept, String prog, Integer level, String sex, String status,
                   String course, String pay, String reg, String elig, String q) {
        /** the same session and semester with every other filter dropped, over the whole register: what the filter options are drawn from */
        Filters withoutScope() {
            return new Filters(office, session, semester, null, null, null, null, null, null, null, null, null, "ALL", null);
        }

        /** the same filters over the whole register in scope: what the dashboard counts, the students not concerned included */
        Filters everyone() {
            return new Filters(office, session, semester, fac, dept, prog, level, sex, status, course, pay, reg, "ALL", q);
        }
    }

    private Filters filters(String office, String session, Integer semester, String fac, String dept, String prog, Integer level, String sex, String status,
                            String course, String pay, String reg, String elig, String q) {
        String sx = sex == null ? null : sex.trim().toUpperCase();
        String st = status == null ? null : status.trim().toUpperCase();
        String py = pay == null ? null : pay.trim().toUpperCase();
        String rg = reg == null ? null : reg.trim().toUpperCase();
        String el = elig == null ? null : elig.trim().toUpperCase();
        return new Filters(office, session(session), semester == null || semester < 1 || semester > 3 ? null : semester,
                blank(fac), blank(dept), blank(prog), level, "M".equals(sx) || "F".equals(sx) ? sx : null, STATUSES.contains(st == null ? "" : st) ? st : null,
                blank(course) == null ? null : course.trim().toUpperCase(), PAY.contains(py == null ? "" : py) ? py : null,
                "REGISTERED".equals(rg) || "NOT_REGISTERED".equals(rg) ? rg : null,
                ELIGIBILITY.contains(el == null ? "" : el) ? el : "INVOLVED",
                q == null || q.isBlank() ? null : "%" + q.trim().toLowerCase() + "%");
    }

    /**
     * the rows the office counts (V366): every undergraduate of the session with the office's own answer — whether its courses concern
     * them (office_required, from finance.gst_eps_rows: the programme's offering at their level, a carryover, a registration), why, and
     * what they owe. A list holds, by default, the students its courses concern or who registered or paid anyway; NOT_APPLICABLE
     * lists the rest, who are never counted unpaid.
     */
    private static final String ROWS = """
            SELECT x.* FROM (
                SELECT p.*,
                       CASE WHEN :office = 'EPS' THEN p.eps_registered ELSE p.gst_registered END AS registered,
                       CASE WHEN :office = 'EPS' THEN p.eps_courses ELSE p.gst_courses END AS courses,
                       CASE WHEN :office = 'EPS' THEN p.eps_required ELSE p.gst_required END AS office_required,
                       CASE WHEN :office = 'EPS' THEN p.eps_reason ELSE p.gst_reason END AS office_reason,
                       CASE WHEN :office = 'EPS' THEN p.eps_carryover ELSE p.gst_carryover END AS office_carryover,
                       CASE WHEN :office = 'EPS' THEN p.eps_completed ELSE p.gst_completed END AS office_completed,
                       CASE WHEN :office = 'EPS' THEN p.eps_owed ELSE p.gst_owed END AS office_owed,
                       (CASE WHEN :office = 'EPS' THEN p.eps_required OR p.eps_registered ELSE p.gst_required OR p.gst_registered OR p.paid > 0 END) AS involved
                  FROM finance.gst_population(:s, :sem) p) x
             WHERE (CASE :elig WHEN 'ALL' THEN true
                               WHEN 'REQUIRED' THEN x.office_required
                               WHEN 'CARRYOVER' THEN x.office_carryover
                               WHEN 'COMPLETED' THEN x.office_completed
                               WHEN 'NOT_APPLICABLE' THEN NOT x.involved
                               WHEN 'REVIEW' THEN x.review AND :office = 'GST'
                               ELSE x.involved END)
               AND (:fac::text IS NULL OR x.faculty_code = :fac)
               AND (:dept::text IS NULL OR x.dept_code = :dept)
               AND (:prog::text IS NULL OR x.programme_code = :prog)
               AND (:level::int IS NULL OR x.level = :level)
               AND (:sex::text IS NULL OR x.sex = :sex)
               AND (:status::text IS NULL OR x.status = :status)
               AND (:pay::text IS NULL OR x.pay_state = :pay)
               AND (:reg::text IS NULL OR (:reg = 'REGISTERED') = x.registered)
               AND (:course::text IS NULL OR EXISTS (SELECT 1 FROM registration.course_registration cr
                                                        JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
                                                        JOIN catalogue.offering o ON o.id = e.offering_id
                                                       WHERE cr.student_id = x.student_id AND cr.session = :s AND o.course_code = :course
                                                         AND (:sem::int IS NULL OR cr.semester = :sem)))
               AND (:q::text IS NULL OR lower(x.surname || ' ' || x.other_names) LIKE :q OR lower(coalesce(x.number, '')) LIKE :q
                    OR lower(x.programme) LIKE :q OR lower(x.department) LIKE :q OR lower(x.faculty) LIKE :q)
            """;

    private JdbcClient.StatementSpec bind(JdbcClient.StatementSpec spec, Filters f) {
        return spec.param("office", f.office()).param("s", f.session()).param("sem", f.semester(), Types.INTEGER)
                .param("fac", f.fac(), Types.VARCHAR).param("dept", f.dept(), Types.VARCHAR).param("prog", f.prog(), Types.VARCHAR)
                .param("level", f.level(), Types.INTEGER).param("sex", f.sex(), Types.VARCHAR).param("status", f.status(), Types.VARCHAR)
                .param("pay", f.pay(), Types.VARCHAR).param("reg", f.reg(), Types.VARCHAR).param("course", f.course(), Types.VARCHAR)
                .param("elig", f.elig()).param("q", f.q(), Types.VARCHAR);
    }

    /** the office's dashboard: the figures in all and by level, faculty, department, programme and gender; the courses; the results; the options the filters offer */
    @GetMapping("/{office}/dashboard")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> dashboard(@PathVariable String office, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                  @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                  @RequestParam(required = false) Integer level, @RequestParam(required = false) String sex, @RequestParam(required = false) String status,
                                  @RequestParam(required = false) String course, @RequestParam(required = false) String payment, @RequestParam(required = false) String registration) {
        String o = office(office);
        Filters f = filters(o, session, semester, fac, dept, prog, level, sex, status, course, payment, registration, null, null);
        // V366: counted over every undergraduate in scope, so the students the office's courses do not concern are counted as such — never as unpaid
        List<Map<String, Object>> groups = bind(jdbc.sql("""
                WITH r AS MATERIALIZED (""" + ROWS + """
                )
                SELECT grouping(faculty_code) AS g_f, grouping(dept_code) AS g_d, grouping(programme_code) AS g_p, grouping(level) AS g_l, grouping(sex) AS g_s,
                       faculty_code, faculty, dept_code, department, programme_code, programme, level, sex,
                       count(*) AS population,
                       count(*) FILTER (WHERE involved) AS total,
                       count(*) FILTER (WHERE office_required) AS required,
                       count(*) FILTER (WHERE NOT involved) AS not_applicable,
                       count(*) FILTER (WHERE office_carryover) AS carryover,
                       count(*) FILTER (WHERE office_completed) AS completed,
                       count(*) FILTER (WHERE office_required AND NOT office_completed) AS outstanding_students,
                       count(*) FILTER (WHERE office_required AND pay_state = 'PAID') AS paid,
                       count(*) FILTER (WHERE office_required AND pay_state = 'EXEMPT') AS exempt,
                       count(*) FILTER (WHERE office_required AND pay_state IN ('NOT_PAID', 'PENDING')) AS unpaid,
                       count(*) FILTER (WHERE office_required AND pay_state = 'PENDING') AS pending,
                       count(*) FILTER (WHERE office_required AND pay_state = 'NOT_STATED') AS not_stated,
                       count(*) FILTER (WHERE review AND :office = 'GST') AS review,
                       count(*) FILTER (WHERE registered) AS registered,
                       count(*) FILTER (WHERE office_required AND NOT registered) AS not_registered,
                       count(*) FILTER (WHERE gst_registered) AS gst_registered,
                       count(*) FILTER (WHERE eps_registered) AS eps_registered,
                       count(*) FILTER (WHERE office_required AND entitled AND NOT registered) AS paid_not_registered,
                       count(*) FILTER (WHERE registered AND required AND NOT entitled) AS registered_unpaid,
                       count(*) FILTER (WHERE involved AND pay_state = 'PAID' AND pay_source = 'LEGACY_PORTAL') AS paid_legacy,
                       count(*) FILTER (WHERE involved AND pay_state = 'PAID' AND pay_source = 'CURRENT_PORTAL') AS paid_current,
                       count(*) FILTER (WHERE involved AND sex = 'M') AS male, count(*) FILTER (WHERE involved AND sex = 'F') AS female,
                       coalesce(sum(paid) FILTER (WHERE involved), 0) AS revenue,
                       coalesce(sum(CASE WHEN required AND stated AND NOT entitled THEN fee - paid ELSE 0 END) FILTER (WHERE office_required), 0) AS outstanding,
                       coalesce(sum(courses), 0) AS course_registrations
                  FROM r
                 GROUP BY GROUPING SETS ((), (faculty_code, faculty), (faculty_code, faculty, dept_code, department),
                                         (faculty_code, faculty, dept_code, department, programme_code, programme), (level), (sex))
                 ORDER BY faculty, department, programme, level, sex
                """), f.everyone()).query().listOfRows();
        Map<String, Object> totals = null;
        List<Map<String, Object>> byFaculty = new ArrayList<>(), byDepartment = new ArrayList<>(), byProgramme = new ArrayList<>(), byLevel = new ArrayList<>(), byGender = new ArrayList<>();
        for (Map<String, Object> g : groups) {
            int gf = n(g, "g_f"), gd = n(g, "g_d"), gp = n(g, "g_p"), gl = n(g, "g_l"), gs = n(g, "g_s");
            Map<String, Object> row = counts(g);
            if (gs == 0) { row.put("sex", g.get("sex")); byGender.add(row); continue; }
            if (gl == 0) { row.put("level", g.get("level")); byLevel.add(row); continue; }
            if (gf == 1 && gd == 1 && gp == 1) { totals = row; continue; }
            if (gp == 0) { row.put("programme_code", g.get("programme_code")); row.put("programme", g.get("programme")); row.put("dept_code", g.get("dept_code")); row.put("department", g.get("department")); row.put("faculty_code", g.get("faculty_code")); byProgramme.add(row); }
            else if (gd == 0) { row.put("dept_code", g.get("dept_code")); row.put("department", g.get("department")); row.put("faculty_code", g.get("faculty_code")); row.put("faculty", g.get("faculty")); byDepartment.add(row); }
            else { row.put("faculty_code", g.get("faculty_code")); row.put("faculty", g.get("faculty")); byFaculty.add(row); }
        }
        if (totals == null) totals = counts(Map.of());

        List<Map<String, Object>> courses = jdbc.sql("SELECT * FROM finance.gst_course_stats(:s, :sem, :o)")
                .param("s", f.session()).param("sem", f.semester(), Types.INTEGER).param("o", o).query().listOfRows();
        long pending = 0, submitted = 0, published = 0, active = 0, registrations = 0;
        for (Map<String, Object> c : courses) {
            String stage = (String) c.get("stage");
            if (stage == null || "ENTRY".equals(stage)) pending++;
            else if ("PUBLISHED".equals(stage)) published++;
            else submitted++;
            if (!"ENDED".equals(c.get("state"))) active++;
            registrations += ((Number) c.get("registered")).longValue();
        }

        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", f.session());
        out.put("semester", f.semester());
        out.put("filters", Map.of("fac", str(f.fac()), "dept", str(f.dept()), "prog", str(f.prog()), "level", f.level() == null ? "" : String.valueOf(f.level()),
                "sex", str(f.sex()), "status", str(f.status()), "course", str(f.course()), "payment", str(f.pay()), "registration", str(f.reg())));
        out.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session ORDER BY name DESC").query().listOfRows());
        out.put("semesters", jdbc.sql("SELECT number, state FROM policy.semester WHERE session = :s ORDER BY number").param("s", f.session()).query().listOfRows());
        out.put("fee", Map.of("rules", rules(f.session(), false), "setting", setting()));
        out.put("totals", totals);
        out.put("byLevel", byLevel);
        out.put("byFaculty", byFaculty);
        out.put("byDepartment", byDepartment);
        out.put("byProgramme", byProgramme);
        out.put("byGender", byGender);
        out.put("courses", courses);
        out.put("results", Map.of("pending", pending, "submitted", submitted, "published", published, "activeCourses", active, "totalCourses", courses.size(), "registrations", registrations));
        // V323: the old-portal GST payments reconciled for the session — what came in, what stands, what waits
        out.put("legacy", jdbc.sql("SELECT * FROM finance.legacy_gst_summary(NULL, :s)").param("s", f.session()).query().singleRow());
        // V367: the office's courses bound to programmes but not opened this session — their students owe nothing until they are
        out.put("gaps", gaps(f.session(), o));
        // V369: course moves to confirm and requests between the offices, waiting on the courses page
        out.put("waiting", waiting(o));
        // V370: whom the office's notices reach
        out.put("reach", reach(o));
        out.put("options", options(f));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** the students behind a figure: the same rows, paged, searched, in the order a people report takes */
    @GetMapping("/{office}/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@PathVariable String office, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester,
                                 @RequestParam(required = false) String fac, @RequestParam(required = false) String dept, @RequestParam(required = false) String prog,
                                 @RequestParam(required = false) Integer level, @RequestParam(required = false) String sex, @RequestParam(required = false) String status,
                                 @RequestParam(required = false) String course, @RequestParam(required = false) String payment, @RequestParam(required = false) String registration,
                                 @RequestParam(required = false) String eligibility,
                                 @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        String o = office(office);
        Filters f = filters(o, session, semester, fac, dept, prog, level, sex, status, course, payment, registration, eligibility, q);
        int sz = Math.max(1, Math.min(size, 500)), pg = Math.max(0, page);
        long total = bind(jdbc.sql("WITH r AS (" + ROWS + ") SELECT count(*) FROM r"), f).query(Long.class).single();
        List<Map<String, Object>> rows = bind(jdbc.sql("""
                WITH r AS (""" + ROWS + """
                )
                SELECT r.student_id, r.number, r.surname, r.other_names, r.sex, r.faculty_code, r.faculty, r.dept_code, r.department, r.programme_code, r.programme,
                       r.level, r.status, r.entry_mode, r.required, r.fee, r.stated, r.paid, r.entitled, r.pay_state, r.reference, r.paid_at,
                       r.gst_registered, r.eps_registered, r.gst_courses, r.eps_courses, r.registered_at, r.pay_source,
                       r.office_required, r.office_reason, r.office_carryover, r.office_completed, r.office_owed, r.review, r.gst_reason, r.eps_reason,
                       (SELECT string_agg(o.course_code, ', ' ORDER BY o.course_code)
                          FROM registration.course_registration cr JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
                          JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.general_office = :office
                         WHERE cr.student_id = r.student_id AND cr.session = :s AND (:sem::int IS NULL OR cr.semester = :sem)) AS registered_courses,
                       (SELECT string_agg(DISTINCT sh.stage, ', ')
                          FROM registration.course_registration cr JOIN registration.entry e ON e.registration_id = cr.id AND e.status <> 'DROPPED'
                          JOIN catalogue.offering o ON o.id = e.offering_id JOIN catalogue.course c ON c.code = o.course_code AND c.general_office = :office
                          JOIN assessment.score_sheet sh ON sh.offering_id = o.id
                         WHERE cr.student_id = r.student_id AND cr.session = :s AND (:sem::int IS NULL OR cr.semester = :sem)) AS result_stages
                  FROM r
                 ORDER BY r.surname, r.other_names, r.number
                 LIMIT :n OFFSET :off
                """), f).param("n", sz).param("off", pg * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", f.session());
        out.put("semester", f.semester());
        out.put("eligibility", f.elig());
        out.put("total", total);
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows);
        return out;
    }

    /** one student's GST/EPS standing, for the drill-down */
    @GetMapping("/{office}/students/{id}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable String office, @PathVariable UUID id, @RequestParam(required = false) String session) {
        String o = office(office);
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", s);
        out.put("student", jdbc.sql("""
                SELECT st.id, coalesce(st.matric_no, st.admission_no) AS number, st.surname, st.other_names, st.sex, st.current_level AS level, st.status, st.entry_mode,
                       p.code AS programme_code, p.name AS programme, d.code AS dept_code, d.name AS department, f.code AS faculty_code, f.name AS faculty
                  FROM people.student st JOIN ref.programme p ON p.code = st.programme_code JOIN ref.department d ON d.code = p.dept_code JOIN ref.faculty f ON f.code = d.faculty_code
                 WHERE st.id = :id
                """).param("id", id).query().listOfRows().stream().findFirst().orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("student", id)));
        out.put("entitlement", jdbc.sql("SELECT * FROM finance.gst_entitlement(:id, :s)").param("id", id).param("s", s).query().singleRow());
        // V366: "why is this student paying GST/EPS?" — the eligibility, its reasons and every GST/EPS course that concerns them
        out.put("explain", GstEpsExplain.read(jdbc, id, s));
        out.put("payments", jdbc.sql("""
                SELECT r.reference, r.receipt_no, r.amount, r.generated_at, r.confirmed_at, r.channel, r.expires_at, r.purpose
                  FROM finance.payment_reference r WHERE r.student_id = :id AND r.purpose LIKE 'GST fee %' ORDER BY r.generated_at DESC
                """).param("id", id).query().listOfRows());
        out.put("courses", jdbc.sql("""
                SELECT cr.session, cr.semester, cr.status AS registration_status, c.code, c.title, c.units, c.general_office, e.entry_type, e.status AS entry_status,
                       sh.stage, (SELECT ls.total FROM assessment.latest_scores(sh.id) ls WHERE ls.student_id = :id) AS total,
                       (SELECT ls.grade FROM assessment.latest_scores(sh.id) ls WHERE ls.student_id = :id) AS grade
                  FROM registration.course_registration cr
                  JOIN registration.entry e ON e.registration_id = cr.id
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course c ON c.code = o.course_code AND c.kind = 'GST' AND c.general_office IS NOT NULL
                  LEFT JOIN assessment.score_sheet sh ON sh.offering_id = o.id
                 WHERE cr.student_id = :id
                 ORDER BY cr.session DESC, cr.semester, c.code
                """).param("id", id).query().listOfRows());
        return out;
    }

    /* ── the office's courses ── */

    /** the office's courses on the catalogue, the session's offerings with their registrations and sheets, the programmes each is offered to */
    @GetMapping("/{office}/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> courses(@PathVariable String office, @RequestParam(required = false) String session, @RequestParam(required = false) Integer semester) {
        String o = office(office);
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", s);
        out.put("semester", semester);
        out.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session ORDER BY name DESC").query().listOfRows());
        out.put("catalogue", jdbc.sql("""
                SELECT c.code, c.title, c.units, c.level, c.semester, c.dept_code, d.name AS department, c.state, c.ended_on, c.general_office, c.ca_max,
                       (SELECT count(*) FROM catalogue.course_offer co WHERE co.course_code = c.code) AS programmes,
                       (SELECT string_agg(co.programme_code || ':' || co.level, ',' ORDER BY co.programme_code, co.level) FROM catalogue.course_offer co WHERE co.course_code = c.code) AS offers,
                       EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = :s) AS offered_this_session
                  FROM catalogue.course c JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.kind = 'GST' AND c.general_office = :o
                 ORDER BY c.state = 'ENDED', c.level, c.code
                """).param("s", s).param("o", o).query().listOfRows());
        out.put("offerings", jdbc.sql("SELECT * FROM finance.gst_course_stats(:s, :sem, :o)").param("s", s).param("sem", semester, Types.INTEGER).param("o", o).query().listOfRows());
        // V366: where each course is offered — the programme, its department and faculty, the level — the mapping the requirement is read from
        out.put("offers", jdbc.sql("""
                SELECT co.course_code, co.level, co.basis, co.track, co.programme_code, p.name AS programme, p.dept_code, d.name AS department,
                       coalesce(d.faculty_code, p.faculty_code) AS faculty_code, f.name AS faculty, co.added_at, co.source,
                       (c.level >= 300 OR co.level >= 300) AS upper_level
                  FROM catalogue.course_offer co
                  JOIN catalogue.course c ON c.code = co.course_code AND c.kind = 'GST' AND c.general_office = :o
                  JOIN ref.programme p ON p.code = co.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
                 ORDER BY co.course_code, co.level, f.name, d.name, p.name
                """).param("o", o).query().listOfRows());
        out.put("gaps", gaps(s, o));
        // V367: the code families that make a course the office's, and the courses an upload marked general that no office runs
        out.put("families", families());
        out.put("unassigned", unassigned(s));
        // V368: every move that touched the office's courses — the reclassification of V367, a claim, a course given back, an upload — to confirm
        out.put("reclassified", reclassified(o));
        // V369: the requests between the two offices for a course, and what waits for this office
        out.put("transfers", transfersOf(o, null));
        out.put("waiting", waiting(o));
        out.put("offerHistory", jdbc.sql("""
                SELECT h.course_code, h.programme_code, p.name AS programme, h.level, h.ended_at, h.reason, h.registrations_carried
                  FROM catalogue.course_offer_history h
                  JOIN catalogue.course c ON c.code = h.course_code AND c.kind = 'GST' AND c.general_office = :o
                  LEFT JOIN ref.programme p ON p.code = h.programme_code
                 ORDER BY h.ended_at DESC LIMIT 200
                """).param("o", o).query().listOfRows());
        out.put("departments", jdbc.sql("SELECT code, name, faculty_code FROM ref.department ORDER BY name").query().listOfRows());
        out.put("programmes", jdbc.sql("SELECT code, name, dept_code, faculty_code FROM ref.programme WHERE NOT archived AND category = 'UNDER GRADUATE' ORDER BY name").query().listOfRows());
        out.put("lecturers", jdbc.sql("""
                SELECT DISTINCT p.id, p.surname || ', ' || p.given_names AS name, p.staff_number
                  FROM iam.person p JOIN iam.office_assignment a ON a.person_id = p.id AND a.office_code = 'lecturer'
                 WHERE a.valid_from <= current_date AND (a.valid_to IS NULL OR a.valid_to >= current_date)
                 ORDER BY 2 LIMIT 2000
                """).query().listOfRows());
        return out;
    }

    public record CourseIn(@NotBlank @Size(max = 20) String code, @NotBlank @Size(max = 200) String title, @NotNull Integer units,
                           @NotNull Integer level, @NotNull Integer semester, @Size(max = 10) String deptCode, Integer caMax) {
    }

    /** a new course of the office: created on the catalogue as kind GST, made live, and owned by the office */
    @PostMapping("/{office}/courses")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> createCourse(@PathVariable String office, @Valid @RequestBody CourseIn body) {
        String o = manage(office);
        String dept = blank(body.deptCode());
        if (dept == null) {
            throw new DomainRuleViolation("GST_COURSE_DEPT", "A course belongs to a department on the register.", new DomainRuleViolation.Remedy("Choose the department that houses the course.", o + " office"));
        }
        String code = jdbc.sql("SELECT catalogue.create_course(:c, :t, :u, :sem, :l, :d, 'GST')")
                .param("c", body.code().trim().toUpperCase()).param("t", body.title().trim()).param("u", body.units()).param("sem", body.semester()).param("l", body.level()).param("d", dept)
                .query(String.class).single();
        jdbc.sql("UPDATE catalogue.course SET general_office = :o, ca_max = coalesce(:ca, ca_max) WHERE code = :c").param("o", o).param("ca", body.caMax(), Types.INTEGER).param("c", code).update();
        jdbc.sql("SELECT catalogue.make_course_live(:c)").param("c", code).query().listOfRows();
        return Map.of("code", code);
    }

    public record CourseEdit(@NotBlank @Size(max = 200) String title, @NotNull Integer units, @NotNull Integer level, @NotNull Integer semester, @Size(max = 10) String deptCode, Integer caMax) {
    }

    /** the office edits its own course: title, units, level, semester, department, CA split */
    @PutMapping("/{office}/courses/{code}")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> editCourse(@PathVariable String office, @PathVariable String code, @Valid @RequestBody CourseEdit body) {
        String o = manage(office);
        code = unslug(code);
        own(o, code);
        int n = jdbc.sql("""
                UPDATE catalogue.course SET title = :t, units = :u, level = :l, semester = :sem, dept_code = coalesce(:d, dept_code), ca_max = coalesce(:ca, ca_max)
                 WHERE code = :c
                """).param("t", body.title().trim()).param("u", body.units()).param("l", body.level()).param("sem", body.semester())
                .param("d", blank(body.deptCode()), Types.VARCHAR).param("ca", body.caMax(), Types.INTEGER).param("c", code).update();
        return Map.of("code", code, "changed", n);
    }

    /** a course deactivated (ended on the catalogue; its offerings and results stand) or reactivated */
    @PostMapping("/{office}/courses/{code}/{action}")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> courseState(@PathVariable String office, @PathVariable String code, @PathVariable String action) {
        String o = manage(office);
        code = unslug(code);
        own(o, code);
        switch (action) {
            case "deactivate" -> jdbc.sql("UPDATE catalogue.course SET state = 'ENDED', ended_on = current_date WHERE code = :c AND state <> 'ENDED'").param("c", code).update();
            case "activate" -> {
                jdbc.sql("UPDATE catalogue.course SET state = 'LIVE', ended_on = NULL WHERE code = :c").param("c", code).update();
            }
            default -> throw new DomainRuleViolation("GST_COURSE_ACTION", "A course is activated or deactivated.", new DomainRuleViolation.Remedy("Name one of the two.", o + " office"));
        }
        return Map.of("code", code, "action", action);
    }

    public record OffersIn(@NotNull List<@NotBlank String> programmes, @NotNull Integer level, @Size(max = 300) String reason) {
    }

    /**
     * which programmes the course is offered to at a level (catalogue.course_offer, basis GST): set whole. V366: through the
     * catalogue's own road — catalogue.bind_offer to add, catalogue.unbind_offer to end, which keeps the ended binding on
     * catalogue.course_offer_history and refuses while a student of that programme is registered on it this session — so the
     * mapping the GST/EPS requirement is read from is never silently lost.
     */
    @PutMapping("/{office}/courses/{code}/offers")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> offers(@PathVariable String office, @PathVariable String code, @Valid @RequestBody OffersIn body) {
        String o = manage(office);
        code = unslug(code);
        own(o, code);
        List<String> wanted = body.programmes().stream().map(p -> p.trim().toUpperCase()).distinct().toList();
        List<String> ended = jdbc.sql("SELECT programme_code FROM catalogue.course_offer WHERE course_code = :c AND level = :l AND basis = 'GST' AND NOT (programme_code = ANY(:p))")
                .param("c", code).param("l", body.level()).param("p", wanted.toArray(String[]::new)).query(String.class).list();
        String why = blank(body.reason()) == null ? "Withdrawn by the " + o + " office" : body.reason().trim();
        for (String p : ended) {
            jdbc.sql("SELECT catalogue.unbind_offer(:c, :p, :l, :r)").param("c", code).param("p", p).param("l", body.level()).param("r", why).query(String.class).single();
        }
        int added = 0;
        for (String p : wanted) {
            boolean had = jdbc.sql("SELECT EXISTS (SELECT 1 FROM catalogue.course_offer WHERE course_code = :c AND programme_code = :p AND level = :l)")
                    .param("c", code).param("p", p).param("l", body.level()).query(Boolean.class).single();
            if (had) continue;
            jdbc.sql("SELECT catalogue.bind_offer(:c, :p, :l, 'GST', NULL, :src)").param("c", code).param("p", p).param("l", body.level()).param("src", o + "_OFFICE")
                    .query().listOfRows();
            added++;
        }
        return Map.of("code", code, "level", body.level(), "programmes", wanted.size(), "added", added, "ended", ended.size());
    }

    public record OfferingIn(@NotBlank String courseCode, @NotBlank String session, @NotNull Integer semester) {
    }

    /** the course offered in a session and semester: the offering the registrations and the score sheet hang on */
    @PostMapping("/{office}/offerings")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> offer(@PathVariable String office, @Valid @RequestBody OfferingIn body) {
        String o = manage(office);
        own(o, body.courseCode());
        UUID id = jdbc.sql("SELECT id FROM catalogue.offering WHERE course_code = :c AND session = :s AND semester = :sem")
                .param("c", body.courseCode()).param("s", body.session()).param("sem", body.semester()).query(UUID.class).optional().orElse(null);
        if (id == null) {
            id = UUID.randomUUID();
            jdbc.sql("INSERT INTO catalogue.offering (id, course_code, session, semester) VALUES (:id, :c, :s, :sem)")
                    .param("id", id).param("c", body.courseCode()).param("s", body.session()).param("sem", body.semester()).update();
        }
        return Map.of("offeringId", id);
    }

    /* ── V367: which office a general course is ── */

    /** who classifies general courses: the two offices (each for its own), the Academic Office and the Super Administrator */
    private static final String CLASSIFIERS = "hasAnyAuthority('OFFICE_gst','OFFICE_eps','OFFICE_academic','OFFICE_super')";

    public record FamilyIn(@Size(max = 3) String office) {
    }

    public record ReturnIn(@NotBlank @Size(max = 300) String reason) {
    }

    /** the code families and the courses an upload marked general that no office runs */
    @GetMapping("/classification")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> classification(@RequestParam(required = false) String session) {
        String s = session(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("families", families());
        out.put("unassigned", unassigned(s));
        return out;
    }

    /** a code family set for an office, or removed (office blank); the courses no office runs that the family reaches are filed under it */
    @PutMapping("/families/{prefix}")
    @PreAuthorize(CLASSIFIERS)
    @Transactional
    Map<String, Object> family(@PathVariable String prefix, @Valid @RequestBody FamilyIn body) {
        String p = prefix == null ? "" : prefix.trim().toUpperCase();
        String o = blank(body.office()) == null ? null : body.office().trim().toUpperCase();
        String own = ownOffice();
        if (own != null) {
            String current = jdbc.sql("SELECT office FROM catalogue.general_family WHERE prefix = :p").param("p", p).query(String.class).optional().orElse(null);
            if ((o != null && !own.equals(o)) || (current != null && !own.equals(current))) {
                throw new AccessDeniedException("The " + own + " office sets its own code families; " + p + " is " + (current == null ? "for the " + o + " office" : "the " + current + " office's") + ".");
            }
        }
        int assigned = jdbc.sql("SELECT catalogue.set_general_family(:p, :o)").param("p", p).param("o", o, Types.VARCHAR).query(Integer.class).single();
        return Map.of("prefix", p, "office", String.valueOf(o), "assigned", assigned, "families", families());
    }

    /** the office takes a course its families do not reach and no office holds (V369: the other office's course comes only by request) */
    @PostMapping("/{office}/courses/{code}/claim")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> claim(@PathVariable String office, @PathVariable String code) {
        String o = manage(office);
        String c = unslug(code);
        jdbc.sql("SELECT code FROM catalogue.claim_general_course(:c, :o)").param("c", c).param("o", o).query(String.class).single();
        return Map.of("code", c, "office", o);
    }

    /** a course an upload marked general that the office does not run, given back to its department as Core; its history stays */
    @PostMapping("/courses/{code}/return")
    @PreAuthorize(CLASSIFIERS)
    @Transactional
    Map<String, Object> giveBack(@PathVariable String code, @Valid @RequestBody ReturnIn body) {
        String c = unslug(code);
        String own = ownOffice();
        if (own != null) {
            String current = jdbc.sql("SELECT general_office FROM catalogue.course WHERE code = :c").param("c", c).query(String.class).optional().orElse(null);
            if (current != null && !own.equals(current)) {
                throw new AccessDeniedException(c + " is the " + current + " office's course; the " + own + " office does not give it back.");
            }
        }
        jdbc.sql("SELECT code FROM catalogue.return_general_course(:c, :r)").param("c", c).param("r", body.reason().trim()).query(String.class).single();
        return Map.of("code", c, "kind", "Core");
    }

    /** V368: the office confirms a move that touched its courses is right (or takes or gives back the course instead) */
    @PostMapping("/{office}/reclassified/{id}/confirm")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> confirmMove(@PathVariable String office, @PathVariable UUID id) {
        String o = manage(office);
        boolean ours = jdbc.sql("SELECT EXISTS (SELECT 1 FROM catalogue.general_reclassification WHERE id = :id AND (before_office = :o OR after_office = :o))")
                .param("id", id).param("o", o).query(Boolean.class).single();
        if (!ours) throw new ng.edu.moaum.portal.shared.NotFound("move", id);
        jdbc.sql("SELECT id FROM catalogue.confirm_reclassification(:id)").param("id", id).query(UUID.class).single();
        return Map.of("id", id, "confirmed", true);
    }

    /* ── V369: a course passes between the GST and EPS offices by request ── */

    public record TransferIn(@NotBlank @Size(max = 500) String reason) {
    }

    public record AnswerIn(@NotNull Boolean accept, @Size(max = 500) String note) {
    }

    /** the office asks the other office for a course it holds; the holding office answers, or the Academic Office decides */
    @PostMapping("/{office}/courses/{code}/request")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> requestCourse(@PathVariable String office, @PathVariable String code, @Valid @RequestBody TransferIn body) {
        String o = manage(office);
        String c = unslug(code);
        return jdbc.sql("SELECT id, course_code, from_office, to_office, state FROM catalogue.request_general_transfer(:c, :o, :r)")
                .param("c", c).param("o", o).param("r", body.reason().trim()).query().singleRow();
    }

    /** the holding office accepts or declines a request (a decline says why); the Academic Office and the Super Administrator decide any */
    @PostMapping("/transfers/{id}/decide")
    @PreAuthorize(CLASSIFIERS)
    @Transactional
    Map<String, Object> decideTransfer(@PathVariable UUID id, @Valid @RequestBody AnswerIn body) {
        Map<String, Object> t = transfer(id);
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        String from = (String) t.get("from_office");
        if (!(acting.equalsIgnoreCase(from) || "academic".equals(acting) || "super".equals(acting))) {
            throw new AccessDeniedException("The " + from + " office answers a request for its own course; the Academic Office may decide it.");
        }
        return jdbc.sql("SELECT id, course_code, from_office, to_office, state FROM catalogue.decide_general_transfer(:id, :a, :n)")
                .param("id", id).param("a", body.accept()).param("n", blank(body.note()), Types.VARCHAR).query().singleRow();
    }

    /** the office that asked withdraws its request while it waits */
    @PostMapping("/transfers/{id}/withdraw")
    @PreAuthorize(CLASSIFIERS)
    @Transactional
    Map<String, Object> withdrawTransfer(@PathVariable UUID id) {
        Map<String, Object> t = transfer(id);
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        String to = (String) t.get("to_office");
        if (!(acting.equalsIgnoreCase(to) || "academic".equals(acting) || "super".equals(acting))) {
            throw new AccessDeniedException("Only the " + to + " office withdraws its own request.");
        }
        return jdbc.sql("SELECT id, course_code, from_office, to_office, state FROM catalogue.withdraw_general_transfer(:id)")
                .param("id", id).query().singleRow();
    }

    /** the requests between the two offices — all of them for the Academic Office's page, the waiting ones first */
    @GetMapping("/transfers")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> transfers(@RequestParam(required = false) String state) {
        String s = state == null || state.isBlank() ? null : state.trim().toUpperCase();
        return transfersOf(null, s);
    }

    private Map<String, Object> transfer(UUID id) {
        return jdbc.sql("SELECT from_office, to_office FROM catalogue.general_transfer WHERE id = :id").param("id", id).query().listOfRows().stream().findFirst()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("request", id));
    }

    private List<Map<String, Object>> transfersOf(String office, String state) {
        return jdbc.sql("""
                SELECT t.id, t.course_code, c.title, c.general_office AS office_now, d.name AS department, t.from_office, t.to_office, t.reason, t.state,
                       t.requested_at, t.requested_office, helpdesk.person_name(t.requested_by) AS requested_by,
                       t.decided_at, t.decided_office, helpdesk.person_name(t.decided_by) AS decided_by, t.decision_note, t.reminded_at, t.escalated_at
                  FROM catalogue.general_transfer t
                  JOIN catalogue.course c ON c.code = t.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE (CAST(:o AS text) IS NULL OR t.from_office = :o OR t.to_office = :o) AND (CAST(:s AS text) IS NULL OR t.state = :s)
                 ORDER BY (t.state = 'PENDING') DESC, coalesce(t.decided_at, t.requested_at) DESC LIMIT 200
                """).param("o", office, Types.VARCHAR).param("s", state, Types.VARCHAR).query().listOfRows();
    }

    public record ChaseIn(@NotNull Integer remindAfterDays, @NotNull Integer escalateAfterDays) {
    }

    /** V370: after how many days an unanswered request is reminded, and after how many it goes to the Academic Office */
    @GetMapping("/transfers/settings")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> chaseSettings() {
        return jdbc.sql("SELECT remind_after_days, escalate_after_days, updated_at, helpdesk.person_name(updated_by) AS updated_by FROM catalogue.general_transfer_setting WHERE id = 1")
                .query().singleRow();
    }

    @PutMapping("/transfers/settings")
    @PreAuthorize("hasAnyAuthority('OFFICE_academic','OFFICE_super')")
    @Transactional
    Map<String, Object> setChaseSettings(@Valid @RequestBody ChaseIn body) {
        jdbc.sql("SELECT id FROM catalogue.set_general_transfer_setting(:r, :e)").param("r", body.remindAfterDays()).param("e", body.escalateAfterDays())
                .query(Integer.class).single();
        return chaseSettings();
    }

    /** V370: who holds the office today and whether a notice reaches them — by email, by text, or not at all; never the address itself */
    private List<Map<String, Object>> reach(String office) {
        return jdbc.sql("SELECT name, email IS NOT NULL AS email, phone IS NOT NULL AS phone FROM catalogue.general_office_reach(:o) ORDER BY name")
                .param("o", office).query().listOfRows();
    }

    /** what waits for the office: moves to confirm, requests it must answer, requests it made */
    private Map<String, Object> waiting(String office) {
        return jdbc.sql("""
                SELECT (SELECT count(*) FROM catalogue.general_reclassification WHERE confirmed_at IS NULL AND (before_office = :o OR after_office = :o)) AS moves_to_confirm,
                       (SELECT count(*) FROM catalogue.general_transfer WHERE state = 'PENDING' AND from_office = :o) AS requests_to_answer,
                       (SELECT count(*) FROM catalogue.general_transfer WHERE state = 'PENDING' AND to_office = :o) AS requests_made
                """).param("o", office).query().singleRow();
    }

    /** the moves that touched the office's courses, the unconfirmed first, with where each course stands now */
    private List<Map<String, Object>> reclassified(String office) {
        return jdbc.sql("""
                SELECT m.id, m.course_code, c.title, c.kind, c.general_office AS office_now, c.general_released_at IS NOT NULL AS given_back,
                       m.before_office, m.after_office, m.before_kind, m.after_kind, m.cause, m.reason, m.changed_at, m.changed_office,
                       m.confirmed_at, m.confirmed_office, d.name AS department,
                       (SELECT count(DISTINCT co.programme_code) FROM catalogue.course_offer co WHERE co.course_code = c.code) AS programmes,
                       (SELECT t.to_office FROM catalogue.general_transfer t WHERE t.course_code = c.code AND t.state = 'PENDING') AS requested_by_office
                  FROM catalogue.general_reclassification m
                  JOIN catalogue.course c ON c.code = m.course_code
                  LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE m.before_office = :o OR m.after_office = :o
                 ORDER BY (m.confirmed_at IS NULL) DESC, m.changed_at DESC LIMIT 500
                """).param("o", office).query().listOfRows();
    }

    /** the acting office when it is the GST or the EPS office, else null */
    private static String ownOffice() {
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        return "gst".equals(acting) ? "GST" : "eps".equals(acting) ? "EPS" : null;
    }

    private List<Map<String, Object>> families() {
        return jdbc.sql("SELECT prefix, office, added_at FROM catalogue.general_family ORDER BY office, prefix").query().listOfRows();
    }

    /** courses of kind GST no office runs: a structure marked them general (status G) but their subject is no office's family */
    private List<Map<String, Object>> unassigned(String session) {
        return jdbc.sql("""
                SELECT c.code, c.title, c.level, c.semester, c.units, c.dept_code, d.name AS department,
                       (SELECT count(DISTINCT co.programme_code) FROM catalogue.course_offer co WHERE co.course_code = c.code) AS programmes,
                       EXISTS (SELECT 1 FROM catalogue.offering o WHERE o.course_code = c.code AND o.session = :s) AS offered_this_session
                  FROM catalogue.course c LEFT JOIN ref.department d ON d.code = c.dept_code
                 WHERE c.kind = 'GST' AND c.general_office IS NULL AND c.state <> 'ENDED' AND c.code NOT LIKE 'DMO %'
                 ORDER BY c.code LIMIT 500
                """).param("s", session).query().listOfRows();
    }

    /**
     * V367: every live course of the office bound to a programme and not yet opened in the session, opened at once, each in its
     * own semester (catalogue.open_gst_offerings); a closed session is refused. Until a course is opened its students owe nothing.
     */
    @PostMapping("/{office}/offerings/open-all")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> openAll(@PathVariable String office, @RequestParam(required = false) String session) {
        String o = manage(office);
        String s = session(session);
        int opened = jdbc.sql("SELECT catalogue.open_gst_offerings(:s, :o)").param("s", s).param("o", o).query(Integer.class).single();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("office", o);
        out.put("session", s);
        out.put("opened", opened);
        out.put("gaps", gaps(s, o));
        return out;
    }

    public record LecturerIn(UUID lecturerId, UUID secondExaminerId) {
    }

    /** the lecturer (and second examiner) of the office's offering, through the catalogue's own allocation */
    @PutMapping("/{office}/offerings/{id}/lecturer")
    @PreAuthorize(MANAGERS)
    @Transactional
    Map<String, Object> lecturer(@PathVariable String office, @PathVariable UUID id, @RequestBody LecturerIn body) {
        String o = manage(office);
        String code = jdbc.sql("SELECT course_code FROM catalogue.offering WHERE id = :id").param("id", id).query(String.class).optional()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("offering", id));
        code = unslug(code);
        own(o, code);
        if (body.lecturerId() == null) {
            jdbc.sql("UPDATE catalogue.offering SET lecturer_id = NULL, second_examiner_id = NULL WHERE id = :id").param("id", id).update();
        } else {
            jdbc.sql("SELECT catalogue.allocate_offering(:id, :l, :x, true)").param("id", id).param("l", body.lecturerId()).param("x", body.secondExaminerId(), Types.OTHER).query().listOfRows();
        }
        return Map.of("offeringId", id, "lecturerId", String.valueOf(body.lecturerId()));
    }

    /* ── the parts ── */

    /** the office named on the path, and whether the acting office may read it: GST sees GST, EPS sees EPS, the rest see both */
    private String office(String path) {
        String o = path == null ? "" : path.trim().toUpperCase();
        if (!OFFICES.contains(o)) throw new ng.edu.moaum.portal.shared.NotFound("office", path);
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        if (("gst".equals(acting) && !"GST".equals(o)) || ("eps".equals(acting) && !"EPS".equals(o))) {
            throw new AccessDeniedException("The " + acting.toUpperCase() + " office reads its own desk; the " + o + " desk is the other office's.");
        }
        return o;
    }

    /** the office whose courses are managed: its own, never the other's */
    private String manage(String path) {
        String o = office(path);
        String acting = AuditContextHolder.current().map(AuditContext::actorOffice).orElse("");
        if (!("super".equals(acting) || acting.equalsIgnoreCase(o))) {
            throw new AccessDeniedException("Only the " + o + " office manages " + o + " courses.");
        }
        return o;
    }

    private void own(String office, String code) {
        String owner = jdbc.sql("SELECT general_office FROM catalogue.course WHERE code = :c").param("c", code).query(String.class).optional()
                .orElseThrow(() -> new ng.edu.moaum.portal.shared.NotFound("course", code));
        if (!office.equals(owner)) {
            throw new AccessDeniedException(code + " is " + (owner == null ? "not a GST/EPS course" : "the " + owner + " office's course") + "; the " + office + " office does not change it.");
        }
    }

    private String session(String asked) {
        if (asked != null && asked.matches("\\d{4}/\\d{4}")) return asked;
        return jdbc.sql("SELECT coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), (SELECT max(name) FROM policy.academic_session WHERE state <> 'PLANNED'), (SELECT max(name) FROM policy.academic_session))")
                .query(String.class).single();
    }

    /** V367: the office's (or, with none, both offices') bound GST/EPS courses not opened in the session */
    private List<Map<String, Object>> gaps(String session, String office) {
        return jdbc.sql("SELECT * FROM catalogue.gst_offering_gaps(:s, :o)").param("s", session).param("o", office, Types.VARCHAR).query().listOfRows();
    }

    private Map<String, Object> setting() {
        return jdbc.sql("SELECT required_for_gst_eps, required_for_all, covers_eps, updated_office, updated_at FROM finance.gst_setting WHERE id = 1").query().singleRow();
    }

    private List<Map<String, Object>> rules(String session, boolean history) {
        return jdbc.sql("""
                SELECT f.id, f.session, f.amount, f.level, f.entry_mode, f.faculty_code, fa.name AS faculty, f.programme_code, p.name AS programme,
                       f.effective_from, f.note, f.stated_office, f.stated_at, f.superseded_at,
                       (SELECT ps.surname || ', ' || ps.given_names FROM iam.person ps WHERE ps.id = f.stated_by) AS stated_by
                  FROM finance.gst_fee f LEFT JOIN ref.faculty fa ON fa.code = f.faculty_code LEFT JOIN ref.programme p ON p.code = f.programme_code
                 WHERE f.session = :s AND (f.superseded_at IS NULL) = NOT :h
                 ORDER BY f.superseded_at DESC NULLS FIRST, (f.programme_code IS NOT NULL) DESC, (f.faculty_code IS NOT NULL) DESC, f.level NULLS FIRST, f.stated_at DESC
                """).param("s", session).param("h", history).query().listOfRows();
    }

    private Map<String, Object> options(Filters f) {
        Map<String, Object> o = new LinkedHashMap<>();
        // one pass over the register (V366: the population is counted by the course engine, so it is read once, not four times)
        List<Map<String, Object>> all = bind(jdbc.sql("""
                WITH r AS MATERIALIZED (""" + ROWS + """
                )
                SELECT DISTINCT 'F'::text AS kind, faculty_code::text AS code, faculty::text AS name, NULL::text AS dept_code, NULL::text AS faculty_code, NULL::int AS level FROM r
                UNION SELECT DISTINCT 'D'::text, dept_code::text, department::text, NULL::text, faculty_code::text, NULL::int FROM r
                UNION SELECT DISTINCT 'P'::text, programme_code::text, programme::text, dept_code::text, faculty_code::text, NULL::int FROM r
                UNION SELECT DISTINCT 'L'::text, NULL::text, NULL::text, NULL::text, NULL::text, level::int FROM r
                """), f.withoutScope()).query().listOfRows();
        List<Map<String, Object>> faculties = new ArrayList<>(), departments = new ArrayList<>(), programmes = new ArrayList<>();
        List<Integer> levels = new ArrayList<>();
        for (Map<String, Object> x : all) {
            switch (String.valueOf(x.get("kind"))) {
                case "F" -> faculties.add(Map.of("code", str(x.get("code")), "name", str(x.get("name"))));
                case "D" -> departments.add(Map.of("code", str(x.get("code")), "name", str(x.get("name")), "faculty_code", str(x.get("faculty_code"))));
                case "P" -> programmes.add(Map.of("code", str(x.get("code")), "name", str(x.get("name")), "dept_code", str(x.get("dept_code")), "faculty_code", str(x.get("faculty_code"))));
                default -> { if (x.get("level") != null) levels.add(((Number) x.get("level")).intValue()); }
            }
        }
        java.util.Comparator<Map<String, Object>> byName = java.util.Comparator.comparing(m -> String.valueOf(m.get("name")));
        faculties.sort(byName);
        departments.sort(byName);
        programmes.sort(byName);
        levels.sort(null);
        o.put("faculties", faculties);
        o.put("departments", departments);
        o.put("programmes", programmes);
        o.put("levels", levels);
        o.put("courses", jdbc.sql("SELECT DISTINCT c.code, c.title, c.level, o.semester FROM catalogue.offering o JOIN catalogue.course c ON c.code = o.course_code WHERE o.session = :s AND c.general_office = :o ORDER BY c.code")
                .param("s", f.session()).param("o", f.office()).query().listOfRows());
        return o;
    }

    private static Map<String, Object> counts(Map<String, Object> g) {
        Map<String, Object> row = new LinkedHashMap<>();
        for (String k : List.of("population", "total", "required", "not_applicable", "carryover", "completed", "outstanding_students", "paid", "exempt", "unpaid", "pending",
                "not_stated", "review", "registered", "not_registered", "gst_registered", "eps_registered",
                "paid_not_registered", "registered_unpaid", "paid_legacy", "paid_current", "male", "female", "course_registrations")) {
            row.put(k, g.getOrDefault(k, 0L));
        }
        row.put("revenue", g.getOrDefault("revenue", BigDecimal.ZERO));
        row.put("outstanding", g.getOrDefault("outstanding", BigDecimal.ZERO));
        return row;
    }

    private static int n(Map<String, Object> g, String k) {
        return ((Number) g.get(k)).intValue();
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String str(Object v) {
        return v == null ? "" : String.valueOf(v);
    }

    /** a course code on the path, its space carried as an underscore (GST_101): a code never holds an underscore */
    private static String unslug(String code) {
        return code == null ? "" : code.replace('_', ' ').trim().toUpperCase();
    }
}
