package ng.edu.moaum.portal.summer;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V735 — the Summer Semester for final-year and spillover students (the University's master prompt of 12 November 2026). The period,
 * its eligibility and the courses a student may take are the database's (registration.summer_period, summer_eligibility,
 * summer_courses); the fees are the Bursary's, stated then published (finance.summer_fee); the student selects outstanding courses of
 * both semesters, pays one reference for what is owed (the programme fee once, a fee a course) through the existing gateways, and the
 * payment's confirmation makes the registration (semester 3 of the session, its Summer classes). The Academic Office sets the period,
 * identifies the eligible, authorises a student, opens the examinations and tells the students; every desk reads the same rows.
 */
@RestController
class SummerController {

    /** who sets the period, authorises a student, opens its examinations and tells the students (the database checks the office again) */
    private static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    /** who reads the Summer's students, courses and figures: the Academic Office and the Registry, the HOD (the department) and the
     *  Dean (the faculty), the Bursary, ICT and the Super Administrator */
    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_hod','OFFICE_dean',"
            + "'OFFICE_bursar','OFFICE_studentaccounts','OFFICE_ict','OFFICE_super','OFFICE_vc','OFFICE_dvc')";
    /** who states and publishes the Summer fees: the Bursary (as the school fees) */
    private static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    /** who publishes (approves) or withdraws a statement: the Bursar, not the officer who drafted it alone */
    private static final String FEE_APPROVERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    private static final String FEE_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super','OFFICE_academic',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict')";
    private static final String SESSION = "^\\d{4}/\\d{4}$";

    private final JdbcClient jdbc;
    private final OfficeScope scope;

    SummerController(JdbcClient jdbc, OfficeScope scope) {
        this.jdbc = jdbc;
        this.scope = scope;
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    /** the offices that read the Summer desk (the active office must be one of them: authority is checked against every office the
     *  token carries, so the active office decides the unit a reader is held to) */
    private static final java.util.Set<String> READER_OFFICES = java.util.Set.of("academic", "registrar", "dregistrar", "hod", "dean", "bursar",
            "studentaccounts", "ict", "super", "vc", "dvc");

    /** V739: the unit the active office is held to (a department office its department, a faculty office its faculty, a sentinel when it
     *  resolves to nothing); refused when the active office does not read the Summer desk */
    private OfficeScope.Bound readerBound() {
        String o = office();
        if (o == null || !READER_OFFICES.contains(o)) {
            throw new org.springframework.security.access.AccessDeniedException("The Summer desk is read in an office that reads it.");
        }
        return scope.bound(null, null, null);
    }

    private static boolean within(OfficeScope.Bound b, Object fac, Object dept, Object prog) {
        return (b.fac() == null || b.fac().equalsIgnoreCase(String.valueOf(fac)))
                && (b.dept() == null || b.dept().equalsIgnoreCase(String.valueOf(dept)))
                && (b.prog() == null || b.prog().equalsIgnoreCase(String.valueOf(prog)));
    }

    /** the Summer a student is shown: the session asked, else the latest Summer OPEN, else the latest set */
    private String sessionOr(String asked) {
        if (asked != null && !asked.isBlank()) {
            return asked.trim();
        }
        return jdbc.sql("""
                SELECT session FROM registration.summer_period ORDER BY (state = 'OPEN') DESC, session DESC LIMIT 1
                """).query(String.class).optional().orElse(null);
    }

    private Map<String, Object> period(String session) {
        return jdbc.sql("""
                SELECT p.*, registration.summer_open(p.session) AS open_now,
                       (SELECT e.id FROM assessment.exam_session e WHERE e.session = p.session AND e.semester = 3 AND e.kind = 'MAIN' AND e.stream = 'REGULAR') AS exam_session_id,
                       (SELECT e.state FROM assessment.exam_session e WHERE e.session = p.session AND e.semester = 3 AND e.kind = 'MAIN' AND e.stream = 'REGULAR') AS exam_state
                  FROM registration.summer_period p WHERE p.session = :s
                """).param("s", session).query().listOfRows().stream().findFirst().orElse(null);
    }

    /* ── the student's own ── */

    public record Select(@NotBlank @Pattern(regexp = SESSION) String session, @NotEmpty @Size(max = 30) List<@NotBlank @Size(max = 16) String> courses) {
    }

    public record Unselect(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 16) String course) {
    }

    public record ForSession(@NotBlank @Pattern(regexp = SESSION) String session) {
    }

    /** the student's Summer: the period, whether they may take it and why, the outstanding courses (each with its own semester and the
     *  session and semester it was failed in, selectable or why not, the fee), the fees published, what is owed and paid, the open
     *  reference, and the registration's courses */
    @GetMapping("/api/v1/me/summer")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String session) {
        UUID student = me(auth);
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        if (s == null) {
            out.put("period", null);
            return out;
        }
        out.put("period", period(s));
        out.put("eligibility", jdbc.sql("SELECT * FROM registration.summer_eligibility(:st, :s)").param("st", student).param("s", s).query().singleRow());
        out.put("courses", jdbc.sql("SELECT * FROM registration.summer_courses(:st, :s)").param("st", student).param("s", s).query().listOfRows());
        out.put("fee", jdbc.sql("SELECT * FROM finance.summer_fee_for(:st, :s)").param("st", student).param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("account", json(jdbc.sql("SELECT registration.summer_account(:st, :s)::text").param("st", student).param("s", s).query(String.class).single()));
        out.put("registered", registered(student, s));
        out.put("payments", jdbc.sql("""
                SELECT r.reference, r.amount, r.purpose, r.confirmed_at, r.receipt_no, r.generated_at, r.expires_at
                  FROM finance.payment_reference r
                 WHERE r.student_id = :st AND r.session = :s AND r.purpose LIKE 'Summer semester fees%' AND r.archived_at IS NULL
                   AND (r.confirmed_at IS NOT NULL OR r.expires_at > now())
                 ORDER BY r.generated_at DESC
                """).param("st", student).param("s", s).query().listOfRows());
        return out;
    }

    /** the courses the Summer registration holds: each with its own semester, the session and semester it was failed in, the units and
     *  the reference that paid it */
    private List<Map<String, Object>> registered(UUID student, String session) {
        return jdbc.sql("""
                SELECT o.course_code, k.title, e.units, k.semester AS course_semester, ch.original_session, ch.original_semester, e.status,
                       pr.reference AS paid_reference, pr.receipt_no, r.status AS registration_status,
                       (SELECT trim(coalesce(p.given_names, '') || ' ' || p.surname) FROM iam.person p WHERE p.id = o.lecturer_id) AS lecturer
                  FROM registration.course_registration r
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course k ON k.code = o.course_code
                  LEFT JOIN registration.summer_charge ch ON ch.student_id = r.student_id AND ch.session = r.session AND ch.kind = 'COURSE'
                                                         AND ch.course_code = o.course_code AND ch.state = 'PAID'
                  LEFT JOIN finance.payment_reference pr ON pr.id = ch.paid_reference_id
                 WHERE r.student_id = :st AND r.session = :s AND r.semester = 3
                 ORDER BY o.course_code
                """).param("st", student).param("s", session).query().listOfRows();
    }

    @PostMapping("/api/v1/me/summer/select")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> select(Authentication auth, @Valid @RequestBody Select body) {
        String[] codes = body.courses().stream().map(c -> c.trim().toUpperCase().replaceAll("\\s+", " ")).distinct().toArray(String[]::new);
        jdbc.sql("SELECT registration.summer_select(:st, :s, CAST(:c AS text[]))::text").param("st", me(auth)).param("s", body.session())
                .param("c", codes, Types.ARRAY).query(String.class).single();
        return mine(auth, body.session());
    }

    @PostMapping("/api/v1/me/summer/unselect")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> unselect(Authentication auth, @Valid @RequestBody Unselect body) {
        jdbc.sql("SELECT registration.summer_unselect(:st, :s, :c)::text").param("st", me(auth)).param("s", body.session()).param("c", body.course())
                .query(String.class).single();
        return mine(auth, body.session());
    }

    /** the reference for everything owed — the open one for exactly that again, else a new one (the stale ones closed); paid through the
     *  existing gateways (POST /api/v1/payments/checkout), confirmed by the gateway's or the bank's word alone, never by the browser */
    @PostMapping("/api/v1/me/summer/reference")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> reference(Authentication auth, @Valid @RequestBody ForSession body) {
        // V741: drawing takes back a course no longer outstanding; when that leaves nothing owed, no reference is drawn
        String ref = jdbc.sql("SELECT coalesce(registration.summer_reference(:st, :s), '')").param("st", me(auth)).param("s", body.session()).query(String.class).single();
        if (ref.isEmpty()) {
            Map<String, Object> none = new LinkedHashMap<>();
            none.put("reference", null);
            none.put("amount", BigDecimal.ZERO);
            none.put("takenBack", true);
            return none;
        }
        BigDecimal amount = jdbc.sql("SELECT amount FROM finance.payment_reference WHERE reference = :r").param("r", ref).query(BigDecimal.class).single();
        return Map.of("reference", ref, "amount", amount);
    }

    /* ── the Academic Office's ── */

    public record PeriodIn(@NotBlank @Pattern(regexp = "^(PLANNED|OPEN|CLOSED)$") String state, LocalDate registrationOpens, LocalDate registrationCloses,
                           LocalDate examsFrom, LocalDate examsTo, LocalDate resultsDue, List<@Pattern(regexp = "^(FINAL_YEAR|SPILLOVER|BEYOND_DURATION|AUTHORISED)$") String> categories,
                           List<@Size(max = 10) String> programmes, List<Integer> levels, @Size(max = 600) String reason) {
    }

    public record Identify(String since, Integer limit) {
    }

    public record Authorise(@NotBlank @Size(max = 40) String number, List<@Size(max = 16) String> courses, @Size(max = 600) String reason, boolean revoke) {
    }

    public record Tell(@NotBlank @Pattern(regexp = "^(OPEN|CLOSING|TIMETABLE)$") String kind) {
    }

    @GetMapping("/api/v1/summer/periods")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> periods() {
        return jdbc.sql("""
                SELECT p.*, registration.summer_open(p.session) AS open_now FROM registration.summer_period p ORDER BY p.session DESC
                """).query().listOfRows();
    }

    @PutMapping("/api/v1/summer/{session}/{year}")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> setPeriod(@PathVariable String session, @PathVariable String year, @Valid @RequestBody PeriodIn body) {
        String s = session + "/" + year;
        jdbc.sql("""
                SELECT registration.summer_set_period(:s, :st, :o, :c, :ef, :et, :rd, CAST(:cat AS text[]), CAST(:pr AS text[]), CAST(:lv AS int[]), :r)
                """).param("s", s).param("st", body.state())
                .param("o", body.registrationOpens(), Types.DATE).param("c", body.registrationCloses(), Types.DATE)
                .param("ef", body.examsFrom(), Types.DATE).param("et", body.examsTo(), Types.DATE).param("rd", body.resultsDue(), Types.DATE)
                .param("cat", body.categories() == null || body.categories().isEmpty() ? null : body.categories().toArray(String[]::new), Types.ARRAY)
                .param("pr", body.programmes() == null || body.programmes().isEmpty() ? null : body.programmes().stream().map(String::trim).toArray(String[]::new), Types.ARRAY)
                .param("lv", body.levels() == null || body.levels().isEmpty() ? null : body.levels().toArray(Integer[]::new), Types.ARRAY)
                .param("r", body.reason(), Types.VARCHAR).query().listOfRows();
        return period(s);
    }

    /** one tranche of the identification of the eligible (each eligibility reads every result of a student): the desk asks again until
     *  none is left; `since` is when this identification began (the students read since then are not read again) */
    @PostMapping("/api/v1/summer/{session}/{year}/identify")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> identify(@PathVariable String session, @PathVariable String year, @RequestBody(required = false) Identify body) {
        String since = body == null || body.since() == null || body.since().isBlank() ? null : body.since();
        int limit = body == null || body.limit() == null ? 400 : Math.max(1, Math.min(body.limit(), 2000));
        String started = since != null ? since : jdbc.sql("SELECT now()::text").query(String.class).single();
        String r = jdbc.sql("SELECT registration.summer_identify(:s, CAST(:since AS timestamptz), :l)::text")
                .param("s", session + "/" + year).param("since", started).param("l", limit).query(String.class).single();
        Map<String, Object> out = new LinkedHashMap<>(json(r));
        out.put("since", started);
        return out;
    }

    /** the Summer's students: the eligible (as last identified) and everyone who selected or paid — a HOD sees the department's, a Dean
     *  the faculty's — with the figures the desks show and the brief asks for */
    @GetMapping("/api/v1/summer/{session}/{year}/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        OfficeScope.Bound b = readerBound();
        List<Map<String, Object>> rows = new ArrayList<>(jdbc.sql("SELECT * FROM registration.summer_students(:s)").param("s", s).query().listOfRows()
                .stream().filter(r -> within(b, r.get("faculty_code"), r.get("dept_code"), r.get("programme_code"))).toList());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("period", period(s));
        out.put("summary", summary(rows));
        out.put("rows", rows);
        out.put("identifiedAt", jdbc.sql("SELECT max(evaluated_at) FROM registration.summer_candidate WHERE session = :s").param("s", s).query().singleRow().get("max"));
        // V739: the paid courses the registration could not take, for the Academic Office to put right and retry
        out.put("issues", jdbc.sql("""
                SELECT i.id, i.student_id, coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name,
                       i.course_code, i.error, i.raised_at, pr.reference, st.programme_code, d.code AS dept_code, d.faculty_code
                  FROM registration.summer_issue i JOIN people.student st ON st.id = i.student_id
                  LEFT JOIN ref.programme p ON p.code = st.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN finance.payment_reference pr ON pr.id = i.reference_id
                 WHERE i.session = :s AND i.resolved_at IS NULL ORDER BY i.raised_at
                """).param("s", s).query().listOfRows().stream().filter(r -> within(b, r.get("faculty_code"), r.get("dept_code"), r.get("programme_code"))).toList());
        return out;
    }

    /** the figures: eligible, begun, completed, courses, payments, results — and by faculty, department, programme and level */
    static Map<String, Object> summary(List<Map<String, Object>> rows) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("eligible", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("eligible"))).count());
        m.put("commenced", rows.stream().filter(r -> !"NOT_STARTED".equals(r.get("payment_state"))).count());
        m.put("completed", rows.stream().filter(r -> r.get("registration_status") != null && num(r.get("courses_registered")) > 0).count());
        m.put("registeredCourses", rows.stream().mapToLong(r -> num(r.get("courses_registered"))).sum());
        m.put("owing", rows.stream().filter(r -> "UNPAID".equals(r.get("payment_state")) || "PART_PAID".equals(r.get("payment_state"))).count());
        m.put("paid", rows.stream().filter(r -> "PAID".equals(r.get("payment_state"))).count());
        m.put("programmeFeesPaid", rows.stream().map(r -> money(r.get("programme_fee_paid"))).reduce(BigDecimal.ZERO, BigDecimal::add));
        m.put("courseFeesPaid", rows.stream().map(r -> money(r.get("course_fees_paid"))).reduce(BigDecimal.ZERO, BigDecimal::add));
        m.put("feesOutstanding", rows.stream().map(r -> money(r.get("programme_fee_due")).add(money(r.get("course_fees_due")))).reduce(BigDecimal.ZERO, BigDecimal::add));
        m.put("resultsPublished", rows.stream().mapToLong(r -> num(r.get("results_published"))).sum());
        m.put("resultsPassed", rows.stream().mapToLong(r -> num(r.get("results_passed"))).sum());
        m.put("resultsFailed", rows.stream().mapToLong(r -> num(r.get("results_failed"))).sum());
        m.put("clearedAll", rows.stream().filter(r -> Boolean.TRUE.equals(r.get("cleared_all"))).count());
        m.put("byFaculty", group(rows, "faculty"));
        m.put("byDepartment", group(rows, "department"));
        m.put("byProgramme", group(rows, "programme"));
        m.put("byLevel", group(rows, "level"));
        return m;
    }

    private static List<Map<String, Object>> group(List<Map<String, Object>> rows, String key) {
        Map<String, long[]> acc = new java.util.TreeMap<>();
        for (Map<String, Object> r : rows) {
            String k = r.get(key) == null ? "—" : String.valueOf(r.get(key));
            long[] a = acc.computeIfAbsent(k, x -> new long[4]);
            if (Boolean.TRUE.equals(r.get("eligible"))) a[0]++;
            if (!"NOT_STARTED".equals(r.get("payment_state"))) a[1]++;
            if (num(r.get("courses_registered")) > 0) a[2]++;
            a[3] += num(r.get("courses_registered"));
        }
        List<Map<String, Object>> out = new ArrayList<>();
        acc.forEach((k, a) -> out.add(Map.of("name", k, "eligible", a[0], "commenced", a[1], "registered", a[2], "courses", a[3])));
        return out;
    }

    private static long num(Object o) {
        return o == null ? 0 : ((Number) o).longValue();
    }

    private static BigDecimal money(Object o) {
        return o == null ? BigDecimal.ZERO : o instanceof BigDecimal b ? b : new BigDecimal(String.valueOf(o));
    }

    /** the Summer's courses: each class, its lecturer, the students registered by the semester the course belongs to, the results */
    @GetMapping("/api/v1/summer/{session}/{year}/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        OfficeScope.Bound b = readerBound();   // V739: whatever office is active, a unit office is held to its unit (a sentinel when it resolves to nothing)
        String dept = b.dept();
        String fac = b.fac();
        return jdbc.sql("""
                SELECT o.id AS offering_id, o.course_code, k.title, k.units, k.semester AS course_semester, k.dept_code, d.name AS department,
                       (SELECT trim(coalesce(p.given_names, '') || ' ' || p.surname) FROM iam.person p WHERE p.id = o.lecturer_id) AS lecturer,
                       count(e.*) FILTER (WHERE e.status NOT IN ('DROPPED', 'WITHDRAWN')) AS registered,
                       count(ch.*) FILTER (WHERE ch.original_semester = 1) AS failed_in_first,
                       count(ch.*) FILTER (WHERE ch.original_semester = 2) AS failed_in_second,
                       (SELECT count(*) FROM assessment.score_sheet sh WHERE sh.offering_id = o.id) AS sheets,
                       (SELECT sh.stage FROM assessment.score_sheet sh WHERE sh.offering_id = o.id ORDER BY sh.published_at NULLS LAST LIMIT 1) AS sheet_stage
                  FROM catalogue.offering o
                  JOIN catalogue.course k ON k.code = o.course_code
                  LEFT JOIN ref.department d ON d.code = k.dept_code
                  LEFT JOIN registration.entry e ON e.offering_id = o.id
                  LEFT JOIN registration.course_registration r ON r.id = e.registration_id
                  LEFT JOIN registration.summer_charge ch ON ch.student_id = r.student_id AND ch.session = o.session AND ch.kind = 'COURSE'
                                                         AND ch.course_code = o.course_code AND ch.state = 'PAID'
                 WHERE o.session = :s AND o.semester = 3 AND o.stream = 'REGULAR'
                   AND (CAST(:dept AS text) IS NULL OR upper(k.dept_code) = upper(:dept))
                   AND (CAST(:fac AS text) IS NULL OR upper(d.faculty_code) = upper(:fac))
                 GROUP BY o.id, o.course_code, k.title, k.units, k.semester, k.dept_code, d.name
                 ORDER BY d.name, o.course_code
                """).param("s", s).param("dept", dept, Types.VARCHAR).param("fac", fac, Types.VARCHAR).query().listOfRows();
    }

    /** the Academic Office admits a student for an approved academic reason (with the courses it names), or withdraws that */
    @PostMapping("/api/v1/summer/{session}/{year}/authorise")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> authorise(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Authorise body) {
        UUID student = jdbc.sql("SELECT id FROM people.student WHERE upper(matric_no) = upper(:n) OR upper(admission_no) = upper(:n) LIMIT 1")
                .param("n", body.number().trim()).query(UUID.class).optional().orElseThrow(() -> new NotFound("student", body.number()));
        jdbc.sql("SELECT registration.summer_authorise(:s, :st, CAST(:c AS text[]), :r, :rv)").param("s", session + "/" + year).param("st", student)
                .param("c", body.courses() == null ? null : body.courses().toArray(String[]::new), Types.ARRAY)
                .param("r", body.reason(), Types.VARCHAR).param("rv", body.revoke()).query().listOfRows();
        Map<String, Object> e = jdbc.sql("SELECT * FROM registration.summer_eligibility(:st, :s)").param("st", student).param("s", session + "/" + year).query().singleRow();
        return Map.of("student", student, "eligibility", e);
    }

    /** the students told, once an event: the Summer open (every eligible student), closing (the eligible who have not completed), the
     *  examinations (every registered student) — through the notification engine's templates, one message a student and channel */
    @PostMapping("/api/v1/summer/{session}/{year}/tell")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> tell(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Tell body) {
        String s = session + "/" + year;
        Map<String, Object> p = period(s);
        if (p == null) {
            throw new DomainRuleViolation("NO_SUMMER", "The Summer Semester of " + s + " is not set.", new DomainRuleViolation.Remedy("Set the period first.", "Academic Office"));
        }
        // V739: the window and the examination dates the notice names must be set, and the Summer not closed; the event names its dates,
        // so a changed window or timetable is told again (the same one never twice)
        boolean closed = "CLOSED".equals(p.get("state"));
        if (("OPEN".equals(body.kind()) || "CLOSING".equals(body.kind())) && (closed || p.get("registration_opens") == null || p.get("registration_closes") == null)) {
            throw new DomainRuleViolation("SUMMER_NOT_TO_TELL", closed ? "The Summer Semester of " + s + " is closed." : "The registration window is not dated.",
                    new DomainRuleViolation.Remedy("Date the registration window (and keep the Summer open or planned) before telling the students.", "Academic Office"));
        }
        if ("CLOSING".equals(body.kind()) && !"OPEN".equals(p.get("state"))) {
            throw new DomainRuleViolation("SUMMER_NOT_TO_TELL", "A reminder is sent while the Summer is open.",
                    new DomainRuleViolation.Remedy("Open the Summer first.", "Academic Office"));
        }
        if ("TIMETABLE".equals(body.kind()) && (p.get("exams_from") == null || p.get("exams_to") == null)) {
            throw new DomainRuleViolation("SUMMER_NOT_TO_TELL", "The examinations are not dated from and to.",
                    new DomainRuleViolation.Remedy("Date the examinations on the period first.", "Academic Office"));
        }
        String sql = switch (body.kind()) {
            case "OPEN" -> """
                    SELECT count(*) FILTER (WHERE platform.tell_student(c.student_id, 'SUMMER_OPEN', NULL,
                               jsonb_build_object('SESSION', :s, 'OPENS', to_char(p.registration_opens, 'DD Mon YYYY'), 'CLOSES', to_char(p.registration_closes, 'DD Mon YYYY'),
                                                  'OUTSTANDING', c.outstanding), 'SUMMER_OPEN:' || :s || ':' || p.registration_opens || ':' || p.registration_closes) > 0)
                      FROM registration.summer_candidate c JOIN registration.summer_period p ON p.session = c.session
                     WHERE c.session = :s AND c.eligible
                    """;
            case "CLOSING" -> """
                    SELECT count(*) FILTER (WHERE platform.tell_student(c.student_id, 'SUMMER_CLOSING', NULL,
                               jsonb_build_object('SESSION', :s, 'CLOSES', to_char(p.registration_closes, 'DD Mon YYYY')), 'SUMMER_CLOSING:' || :s || ':' || p.registration_closes) > 0)
                      FROM registration.summer_candidate c JOIN registration.summer_period p ON p.session = c.session
                     WHERE c.session = :s AND c.eligible
                       AND NOT EXISTS (SELECT 1 FROM registration.summer_charge ch WHERE ch.student_id = c.student_id AND ch.session = :s AND ch.state = 'PAID')
                    """;
            default -> """
                    SELECT count(*) FILTER (WHERE platform.tell_student(r.student_id, 'SUMMER_TIMETABLE', NULL,
                               jsonb_build_object('SESSION', :s, 'EXAMS_FROM', to_char(p.exams_from, 'DD Mon YYYY'), 'EXAMS_TO', to_char(p.exams_to, 'DD Mon YYYY')),
                               'SUMMER_TIMETABLE:' || :s || ':' || p.exams_from || ':' || p.exams_to) > 0)
                      FROM registration.course_registration r JOIN registration.summer_period p ON p.session = r.session
                     WHERE r.session = :s AND r.semester = 3 AND r.status IN ('APPROVED', 'LOCKED') AND p.exams_from IS NOT NULL
                    """;
        };
        long told = jdbc.sql(sql).param("s", s).query(Long.class).single();
        return Map.of("kind", body.kind(), "told", told);
    }

    /** V739: a paid Summer course the registration could not take, retried once what stopped it is put right */
    @PostMapping("/api/v1/summer/issues/{id}/retry")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> retry(@PathVariable UUID id) {
        return json(jdbc.sql("SELECT registration.summer_issue_retry(:id)::text").param("id", id).query(String.class).single());
    }

    /** the Summer's examination session opened, or its score sheets released to the lecturers (the existing examination engine) */
    @PostMapping("/api/v1/summer/{session}/{year}/exams/{act}")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> exams(@PathVariable String session, @PathVariable String year, @PathVariable String act) {
        String s = session + "/" + year;
        UUID id = jdbc.sql("SELECT id FROM assessment.exam_session WHERE session = :s AND semester = 3 AND kind = 'MAIN' AND stream = 'REGULAR'")
                .param("s", s).query(UUID.class).optional()
                .orElseThrow(() -> new DomainRuleViolation("SUMMER_EXAMS_NOT_DATED", "The Summer's examinations are not dated.",
                        new DomainRuleViolation.Remedy("Date the examinations on the period first.", "Academic Office")));
        switch (act) {
            case "open" -> jdbc.sql("SELECT assessment.open_exam_session(:id)").param("id", id).query().listOfRows();
            case "release-sheets" -> jdbc.sql("SELECT assessment.release_exam_sheets(:id)").param("id", id).query().listOfRows();
            default -> throw new NotFound("examination act", act);
        }
        return period(s);
    }

    /* ── the Bursary's ── */

    public record FeeIn(@NotBlank @Pattern(regexp = SESSION) String session, @Size(max = 10) String programme,
                        @NotNull @DecimalMin(value = "1") BigDecimal programmeFee, @NotNull @DecimalMin(value = "1") BigDecimal courseFee,
                        LocalDate effectiveFrom, @Size(max = 600) String reason) {
    }

    public record Why(@NotBlank @Size(min = 10, max = 600) String reason) {
    }

    public record Settle(@NotBlank @Pattern(regexp = "^(APPLIED|REFUNDED)$") String state, @NotBlank @Size(min = 10, max = 600) String note) {
    }

    /** V739: Summer money received beyond the charges it could pay, settled by the Bursar — applied (to what the student owes) or refunded —
     *  with a note; the money itself is moved on the desks that move money */
    @PostMapping("/api/v1/finance/summer-credits/{id}/settle")
    @PreAuthorize(FEE_APPROVERS)
    @Transactional
    Map<String, Object> settle(@PathVariable UUID id, @Valid @RequestBody Settle body) {
        // V742: only a credit whose payment still stands as the student's Summer payment (one archived is held until restored; one moved
        // off the Summer is settled by the move itself). V751: the database checks it all again, and refuses "Applied" by hand for a
        // credit that is the whole of its payment (SUMMER_CREDIT_MOVE_IT: the payment is moved on the correction desk, which records it)
        String state = jdbc.sql("SELECT registration.summer_credit_settle(:id, :st, :n)")
                .param("id", id).param("st", body.state()).param("n", body.note().trim()).query(String.class).single();
        return Map.of("id", id, "state", state);
    }

    public record Reopen(@NotBlank @Size(min = 10, max = 600) String reason) {
    }

    /** V751: a Summer credit the Bursar settled by hand in error is reopened, with a reason, while its payment stands as the Summer
     *  payment — the payment may then be moved or archived */
    @PostMapping("/api/v1/finance/summer-credits/{id}/reopen")
    @PreAuthorize(FEE_APPROVERS)
    @Transactional
    Map<String, Object> reopen(@PathVariable UUID id, @Valid @RequestBody Reopen body) {
        String state = jdbc.sql("SELECT registration.summer_credit_reopen(:id, :r)").param("id", id).param("r", body.reason().trim())
                .query(String.class).single();
        return Map.of("id", id, "state", state);
    }

    @GetMapping("/api/v1/finance/summer-fees")
    @PreAuthorize(FEE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> fees(@RequestParam(required = false) String session) {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT f.*, p.name AS programme_name,
                       (SELECT count(*) FROM registration.summer_charge c WHERE c.fee_id = f.id AND c.state <> 'CANCELLED') AS charges
                  FROM finance.summer_fee f LEFT JOIN ref.programme p ON p.code = f.programme_code
                 WHERE CAST(:s AS text) IS NULL OR f.session = :s
                 ORDER BY f.session DESC, f.programme_code NULLS FIRST, f.effective_from DESC, f.stated_at DESC
                """).param("s", session == null || session.isBlank() ? null : session.trim(), Types.VARCHAR).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("fees", rows);
        // the programmes a fee may be stated for alone: the undergraduate programmes on the register
        out.put("programmes", jdbc.sql("SELECT code, name FROM ref.programme WHERE category = 'UNDER GRADUATE' AND NOT coalesce(archived, false) ORDER BY name")
                .query().listOfRows());
        // V739: unapplied Summer money (a reference confirmed after its charges were taken back or paid by another)
        out.put("credits", jdbc.sql("""
                SELECT c.id, c.session, c.amount, c.state, c.created_at, c.settled_at, c.settled_note, pr.reference, pr.receipt_no,
                       coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name
                  FROM registration.summer_credit c JOIN people.student st ON st.id = c.student_id
                  JOIN finance.payment_reference pr ON pr.id = c.reference_id
                 WHERE (CAST(:s AS text) IS NULL OR c.session = :s)
                   AND pr.archived_at IS NULL AND pr.purpose LIKE 'Summer semester fees%'   -- V741: while the payment stands as a Summer payment
                 ORDER BY (c.state = 'OPEN') DESC, c.created_at DESC
                """).param("s", session == null || session.isBlank() ? null : session.trim(), Types.VARCHAR).query().listOfRows());
        out.put("collections", jdbc.sql("""
                SELECT c.session,
                       coalesce(sum(c.amount) FILTER (WHERE c.kind = 'PROGRAMME' AND c.state = 'PAID'), 0) AS programme_fees_paid,
                       count(*) FILTER (WHERE c.kind = 'PROGRAMME' AND c.state = 'PAID') AS programme_fees_paid_count,
                       coalesce(sum(c.amount) FILTER (WHERE c.kind = 'COURSE' AND c.state = 'PAID'), 0) AS course_fees_paid,
                       count(*) FILTER (WHERE c.kind = 'COURSE' AND c.state = 'PAID') AS course_fees_paid_count,
                       coalesce(sum(c.amount) FILTER (WHERE c.kind = 'PROGRAMME' AND c.state = 'DUE'), 0) AS programme_fees_due,
                       coalesce(sum(c.amount) FILTER (WHERE c.kind = 'COURSE' AND c.state = 'DUE'), 0) AS course_fees_due
                  FROM registration.summer_charge c
                 WHERE CAST(:s AS text) IS NULL OR c.session = :s
                 GROUP BY c.session ORDER BY c.session DESC
                """).param("s", session == null || session.isBlank() ? null : session.trim(), Types.VARCHAR).query().listOfRows());
        return out;
    }

    /** a statement of the Summer fees, a DRAFT until published (a draft is never charged) */
    @PostMapping("/api/v1/finance/summer-fees")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> stateFee(@Valid @RequestBody FeeIn body) {
        UUID who = AuditContextHolder.current().map(c -> c.actorId()).orElseThrow();
        UUID id = jdbc.sql("""
                INSERT INTO finance.summer_fee (session, programme_code, programme_fee, course_fee, effective_from, reason, stated_by, stated_office)
                VALUES (:s, :p, :pf, :cf, coalesce(CAST(:ef AS date), current_date), :r, :who, :o) RETURNING id
                """).param("s", body.session()).param("p", body.programme() == null || body.programme().isBlank() ? null : body.programme().trim(), Types.VARCHAR)
                .param("pf", body.programmeFee()).param("cf", body.courseFee()).param("ef", body.effectiveFrom(), Types.DATE)
                .param("r", body.reason(), Types.VARCHAR).param("who", who).param("o", office()).query(UUID.class).single();
        return Map.of("id", id, "state", "DRAFT");
    }

    @PostMapping("/api/v1/finance/summer-fees/{id}/publish")
    @PreAuthorize(FEE_APPROVERS)
    @Transactional
    Map<String, Object> publish(@PathVariable UUID id) {
        UUID who = AuditContextHolder.current().map(c -> c.actorId()).orElseThrow();
        int n = jdbc.sql("UPDATE finance.summer_fee SET state = 'PUBLISHED', published_by = :w, published_office = :o, published_at = now() WHERE id = :id AND state = 'DRAFT'")
                .param("w", who).param("o", office()).param("id", id).update();
        if (n == 0) {
            throw new DomainRuleViolation("SUMMER_FEE_NOT_DRAFT", "Only a draft is published.", new DomainRuleViolation.Remedy("State a new fee.", "Bursary"));
        }
        return Map.of("id", id, "state", "PUBLISHED");
    }

    /** a published fee withdrawn (with the reason): new charges no longer take it; charges already made keep the figure they were made at */
    @PostMapping("/api/v1/finance/summer-fees/{id}/withdraw")
    @PreAuthorize(FEE_APPROVERS)
    @Transactional
    Map<String, Object> withdraw(@PathVariable UUID id, @Valid @RequestBody Why body) {
        UUID who = AuditContextHolder.current().map(c -> c.actorId()).orElseThrow();
        int n = jdbc.sql("UPDATE finance.summer_fee SET state = 'WITHDRAWN', withdrawn_by = :w, withdrawn_at = now(), withdrawn_reason = :r WHERE id = :id AND state = 'PUBLISHED'")
                .param("w", who).param("r", body.reason().trim()).param("id", id).update();
        if (n == 0) {
            throw new DomainRuleViolation("SUMMER_FEE_NOT_PUBLISHED", "Only a published fee is withdrawn.", new DomainRuleViolation.Remedy("Delete a draft instead.", "Bursary"));
        }
        return Map.of("id", id, "state", "WITHDRAWN");
    }

    @DeleteMapping("/api/v1/finance/summer-fees/{id}")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> deleteDraft(@PathVariable UUID id) {
        int n = jdbc.sql("DELETE FROM finance.summer_fee WHERE id = :id AND state = 'DRAFT'").param("id", id).update();
        if (n == 0) {
            throw new DomainRuleViolation("SUMMER_FEE_NOT_DRAFT", "Only a draft is deleted; a published fee is withdrawn.", new DomainRuleViolation.Remedy("Withdraw it.", "Bursary"));
        }
        return Map.of("id", id, "deleted", true);
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** a jsonb the database built, as a map the response carries */
    private static Map<String, Object> json(String text) {
        return JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }
}
