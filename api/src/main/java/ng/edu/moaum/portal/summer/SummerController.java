package ng.edu.moaum.portal.summer;

import static ng.edu.moaum.portal.summer.SummerAccess.READERS;
import static ng.edu.moaum.portal.summer.SummerAccess.SESSION;
import static ng.edu.moaum.portal.summer.SummerAccess.SETTERS;
import static ng.edu.moaum.portal.summer.SummerAccess.json;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;
import java.util.stream.Collectors;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotEmpty;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DeadlockRetry;
import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.transaction.support.TransactionTemplate;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

/**
 * V735, V779 — the Summer Semester for final-year and spillover students (the University's master prompts of 12 and 23 November
 * 2026). The period, its eligibility and the courses a student may take are the database's (registration.summer_period,
 * summer_eligibility_of, summer_selectable); the fees are the Bursary's, stated then published (finance.summer_fee); the student
 * selects the courses they believe they still owe from both semesters — no result is needed to select, and a missing result is never
 * read as a pass — pays one reference for what is owed (the programme fee once, a fee a course) through the existing gateways, and the
 * payment's confirmation makes the registration (semester 3 of the session, its Summer classes). The Academic Office then verifies
 * each selection against the record (SummerReviewController). This class holds the student's own doors, the period and its acts
 * (identify, tell, the examinations and their override), the authorisations and the Bursary's fees and credits; the desk's people and
 * figures are SummerReportController's.
 */
@RestController
class SummerController {

    /** who states and publishes the Summer fees: the Bursary (as the school fees) */
    private static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    /** who publishes (approves) or withdraws a statement: the Bursar, not the officer who drafted it alone */
    private static final String FEE_APPROVERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    private static final String FEE_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super','OFFICE_academic',"
            + "'OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict')";

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    /** the acts a passing clash with a payment or another officer may end (identify, a student's reconcile) run in a transaction of
     *  their own and again in a fresh one (DeadlockRetry): a method that is @Transactional would run once */
    private final TransactionTemplate tx;

    SummerController(JdbcClient jdbc, OfficeScope scope, PlatformTransactionManager transactions) {
        this.jdbc = jdbc;
        this.scope = scope;
        this.tx = new TransactionTemplate(transactions);
    }

    private static UUID me(Authentication auth) {
        return UUID.fromString(auth.getName());
    }

    private static String office() {
        return AuditContextHolder.current().map(c -> c.actorOffice()).orElse(null);
    }

    /** a course code as the database keeps it: trimmed, upper case, one space between its words */
    private static String code(String c) {
        return c == null ? null : c.trim().toUpperCase().replaceAll("\\s+", " ");
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

    /** V779: the examination overrides on record (the Academic Office's reasons for an act the gate would refuse) */
    private List<Map<String, Object>> overrides(String session) {
        return jdbc.sql("SELECT act, reason, unverified, set_at FROM registration.summer_exam_override WHERE session = :s ORDER BY act")
                .param("s", session).query().listOfRows();
    }

    /** V779: the period as the desk reads it — the period, the paid courses not yet verified (live: read from results at this
     *  moment, and only where the Summer holds a paid selection at all) and any override of the examination gate */
    private Map<String, Object> deskPeriod(String session) {
        Map<String, Object> p = period(session);
        if (p == null) {
            return null;
        }
        Map<String, Object> out = new LinkedHashMap<>(p);
        boolean paid = Boolean.TRUE.equals(jdbc.sql("""
                SELECT EXISTS (SELECT 1 FROM registration.summer_charge c WHERE c.session = :s AND c.kind = 'COURSE' AND c.state = 'PAID')
                """).param("s", session).query(Boolean.class).single());
        out.put("unverified", paid ? jdbc.sql("SELECT registration.summer_unverified(:s)").param("s", session).query(Integer.class).single() : Integer.valueOf(0));
        out.put("overrides", overrides(session));
        return out;
    }

    /* ── the student's own ── */

    /** where the student says they owe a course: the session and the semester (1 or 2) — the database judges both (SUMMER_ORIGIN_INVALID) */
    public record Origin(@NotBlank @Size(max = 20) String course, @Size(max = 12) String session, Integer semester) {
    }

    /** at most 200 entries of at most 20 characters (as long as a catalogue course code may be: ck_course_code, V776), so that
     *  the database, not bean validation, refuses more than 30 distinct (SUMMER_TOO_MANY) and every other rule about the courses
     *  chosen; every course code the Summer takes is capped at 20 for the same reason */
    public record Select(@NotBlank @Pattern(regexp = SESSION) String session, @NotEmpty @Size(max = 200) List<@NotBlank @Size(max = 20) String> courses,
                         @Size(max = 200) List<@Valid Origin> origins) {
    }

    public record Unselect(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 20) String course) {
    }

    public record ForSession(@NotBlank @Pattern(regexp = SESSION) String session) {
    }

    /** the student's note on a selection of theirs (the database holds it to 500 characters: SUMMER_NOTE_LONG) */
    public record StudentNote(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 20) String course, @NotNull @Size(max = 2000) String note) {
    }

    /** the student's Summer: the period, whether they may take it and why, the courses of the programme and the ones they owe (each
     *  with its own semester, the evidence on record, where they say they owe it, what the Academic Office found, selectable or why
     *  not, the fee), the fees published, what is owed and paid, the summary, the open reference, and the registration's courses.
     *  It writes nothing (ICT Support reads it in a read-only transaction, and the dashboard's card is the slim read): the stored
     *  state is brought up to date by the reconcile the page asks for after it renders */
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
        Map<String, Object> period = period(s);
        out.put("period", period);
        out.put("eligibility", jdbc.sql("SELECT * FROM registration.summer_eligibility(:st, :s)").param("st", student).param("s", s).query().singleRow());
        // no Summer set: nothing is offered (the page says so by the eligibility's reason)
        out.put("courses", period == null ? List.of()
                : jdbc.sql("SELECT * FROM registration.summer_selectable(:st, :s)").param("st", student).param("s", s).query().listOfRows());
        out.put("fee", jdbc.sql("SELECT * FROM finance.summer_fee_for(:st, :s)").param("st", student).param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("account", json(jdbc.sql("SELECT registration.summer_account(:st, :s)::text").param("st", student).param("s", s).query(String.class).single()));
        out.put("summary", json(jdbc.sql("SELECT registration.summer_summary(:st, :s)::text").param("st", student).param("s", s).query(String.class).single()));
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

    /** the dashboard's read: the period, whether the student may take the Summer, the fee and the summary — no pool, no results, no
     *  lock and nothing written. The eligibility is the set reader's (it reads no result), so it carries no count of what the record
     *  says is owed: that figure is the page's own */
    @GetMapping("/api/v1/me/summer/card")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> card(Authentication auth, @RequestParam(required = false) String session) {
        UUID student = me(auth);
        String s = sessionOr(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        if (s == null) {
            out.put("period", null);
            return out;
        }
        out.put("period", period(s));
        Map<String, Object> e = jdbc.sql("SELECT eligible, category, reason FROM registration.summer_eligibility_of(:s, ARRAY[CAST(:st AS uuid)])")
                .param("s", s).param("st", student.toString()).query().singleRow();
        Map<String, Object> eligibility = new LinkedHashMap<>();
        eligibility.put("eligible", e.get("eligible"));
        eligibility.put("category", e.get("category"));
        eligibility.put("outstanding", null);
        eligibility.put("reason", e.get("reason"));
        out.put("eligibility", eligibility);
        out.put("fee", jdbc.sql("SELECT * FROM finance.summer_fee_for(:st, :s)").param("st", student).param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("summary", json(jdbc.sql("SELECT registration.summer_summary(:st, :s)::text").param("st", student).param("s", s).query(String.class).single()));
        return out;
    }

    /** the courses the Summer registration holds: each with its own semester, the session and semester it was failed in, the units,
     *  the reference that paid it, and how it came in and what the Academic Office has found of it (never "carry-over" for a course
     *  the student chose) */
    private List<Map<String, Object>> registered(UUID student, String session) {
        return jdbc.sql("""
                SELECT o.course_code, k.title, e.units, k.semester AS course_semester,
                       coalesce(ch.original_session, sel.original_session) AS original_session,
                       coalesce(ch.original_semester, sel.original_semester) AS original_semester, e.status,
                       pr.reference AS paid_reference, pr.receipt_no, r.status AS registration_status,
                       (SELECT trim(coalesce(p.given_names, '') || ' ' || p.surname) FROM iam.person p WHERE p.id = o.lecturer_id) AS lecturer,
                       coalesce(sel.basis, ch.basis, 'CARRY_OVER') AS basis,
                       sel.state AS verification, sel.verified_via,
                       CASE coalesce(sel.basis, ch.basis, 'CARRY_OVER') WHEN 'STUDENT_SELECTED' THEN 'Student-selected course'
                                                                           WHEN 'AUTHORISED' THEN 'Authorised course' ELSE 'Carry-over' END AS category_label
                  FROM registration.course_registration r
                  JOIN registration.entry e ON e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')
                  JOIN catalogue.offering o ON o.id = e.offering_id
                  JOIN catalogue.course k ON k.code = o.course_code
                  LEFT JOIN registration.summer_charge ch ON ch.student_id = r.student_id AND ch.session = r.session AND ch.kind = 'COURSE'
                                                         AND ch.course_code = o.course_code AND ch.state = 'PAID'
                  LEFT JOIN finance.payment_reference pr ON pr.id = ch.paid_reference_id
                  LEFT JOIN registration.summer_selection sel ON sel.student_id = r.student_id AND sel.session = r.session AND sel.course_code = o.course_code
                 WHERE r.student_id = :st AND r.session = :s AND r.semester = 3
                 ORDER BY o.course_code
                """).param("st", student).param("s", session).query().listOfRows();
    }

    /** the courses chosen, with where the student says they owe each (optional): the database holds the pool and every rule (the
     *  course must be one of the programme's, one owed or one authorised; not passed, not registered, not decided against) */
    @PostMapping("/api/v1/me/summer/select")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> select(Authentication auth, @Valid @RequestBody Select body) {
        String[] codes = body.courses().stream().map(SummerController::code).distinct().toArray(String[]::new);
        String origins = null;
        if (body.origins() != null && !body.origins().isEmpty()) {
            List<Map<String, Object>> list = new ArrayList<>();
            for (Origin o : body.origins()) {
                Map<String, Object> m = new LinkedHashMap<>();
                m.put("course", code(o.course()));
                m.put("session", o.session() == null || o.session().isBlank() ? null : o.session().trim());
                m.put("semester", o.semester());
                list.add(m);
            }
            origins = SummerAccess.JSON.writeValueAsString(list);
        }
        jdbc.sql("SELECT registration.summer_select(:st, :s, CAST(:c AS text[]), CAST(:o AS jsonb))::text").param("st", me(auth)).param("s", body.session())
                .param("c", codes, Types.ARRAY).param("o", origins, Types.VARCHAR).query(String.class).single();
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

    /** V779: a word from the student on a selection of theirs (an answer to the Academic Office's question, or why they owe it) */
    @PostMapping("/api/v1/me/summer/note")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> note(Authentication auth, @Valid @RequestBody StudentNote body) {
        jdbc.sql("SELECT registration.summer_student_note(:st, :s, :c, :n)").param("st", me(auth)).param("s", body.session())
                .param("c", code(body.course())).param("n", body.note().trim()).query().listOfRows();
        return Map.of("ok", true);
    }

    /** V779: the printable confirmation's data — the student's live selections and the courses found not outstanding or rejected,
     *  the fees itemised, the payments; 404 when the student has nothing selected in the session */
    @GetMapping("/api/v1/me/summer/confirmation")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> confirmation(Authentication auth, @RequestParam(required = false) String session) {
        String s = sessionOr(session);
        if (s == null) {
            throw new NotFound("Summer Semester selection", "(no Summer is set)");
        }
        Map<String, Object> c = json(jdbc.sql("SELECT registration.summer_confirmation(:st, :s)::text").param("st", me(auth)).param("s", s).query(String.class).single());
        if (c == null || c.isEmpty() || "NONE".equals(c.get("status"))) {
            throw new NotFound("Summer Semester selection of " + s, "for this student");
        }
        return c;
    }

    /** V779: the page brings the stored verification state up to date against the results now on the portal (a pass taken back,
     *  a failure confirmed, a result rolled back), once after it renders and only when it has something to reconcile; the reading of
     *  the page writes nothing, so this is its own request. ICT Support's view refuses every write before it gets here */
    @PostMapping("/api/v1/me/summer/reconcile")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> reconcile(Authentication auth, @Valid @RequestBody ForSession body) {
        UUID student = me(auth);
        return DeadlockRetry.inTransaction(tx, () -> json(jdbc.sql("SELECT registration.summer_reconcile_student(:st, :s)::text")
                .param("st", student).param("s", body.session()).query(String.class).single()));
    }

    /* ── the Academic Office's ── */

    public record PeriodIn(@NotBlank @Pattern(regexp = "^(PLANNED|OPEN|CLOSED)$") String state, LocalDate registrationOpens, LocalDate registrationCloses,
                           LocalDate examsFrom, LocalDate examsTo, LocalDate resultsDue, List<@Pattern(regexp = "^(FINAL_YEAR|SPILLOVER|BEYOND_DURATION|AUTHORISED)$") String> categories,
                           List<@Size(max = 10) String> programmes, List<Integer> levels, @Size(max = 600) String reason) {
    }

    public record Identify(String since, Integer limit) {
    }

    public record Authorise(@NotBlank @Size(max = 40) String number, List<@Size(max = 20) String> courses, @Size(max = 600) String reason, boolean revoke) {
    }

    /** the students told in tranches of at most 2,000, walked by a cursor (the last student taken): the desk repeats with `after`
     *  set to the `next` of the answer until it is null */
    public record Tell(@NotBlank @Pattern(regexp = "^(OPEN|CLOSING|TIMETABLE)$") String kind, @Min(1) @Max(2000) Integer limit, UUID after) {
    }

    /** the course ceiling: how many courses a student may hold in the Summer (none when absent), and why */
    public record Ceiling(Integer maxCourses, @Size(max = 600) String reason) {
    }

    public record GateOverride(@NotNull @Size(max = 600) String reason) {
    }

    @GetMapping("/api/v1/summer/periods")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> periods() {
        List<Map<String, Object>> rows = jdbc.sql("""
                SELECT p.*, registration.summer_open(p.session) AS open_now FROM registration.summer_period p ORDER BY p.session DESC
                """).query().listOfRows();
        // V779: the overrides of the examination gate come with the list; the live count of unverified courses is a single period's
        // answer (it reads the results of every paid student), so it is null here
        Map<String, List<Map<String, Object>>> overrides = jdbc.sql("SELECT session, act, reason, unverified, set_at FROM registration.summer_exam_override ORDER BY act")
                .query().listOfRows().stream().collect(Collectors.groupingBy(r -> String.valueOf(r.get("session")), LinkedHashMap::new, Collectors.toList()));
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>(r);
            m.put("unverified", null);
            m.put("overrides", overrides.getOrDefault(String.valueOf(r.get("session")), List.of()));
            out.add(m);
        }
        return out;
    }

    /** V779: one period as the desk reads it, with the live count of the paid courses not yet verified and any override of the gate */
    @GetMapping("/api/v1/summer/{session}/{year}/period")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> onePeriod(@PathVariable String session, @PathVariable String year) {
        SummerAccess.readerBound(scope);
        String s = session + "/" + year;
        Map<String, Object> p = deskPeriod(s);
        if (p == null) {
            throw new NotFound("Summer Semester", s);
        }
        return p;
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
        return deskPeriod(s);
    }

    /** V779: the most courses a student may hold in the Summer (cumulative; none when absent), with the reason; a ceiling below what
     *  a student holds never removes a course, it stops further selecting. The database holds the range (SUMMER_CEILING_RANGE) and the
     *  reason (SUMMER_REASON) */
    @PutMapping("/api/v1/summer/{session}/{year}/ceiling")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> ceiling(@PathVariable String session, @PathVariable String year, @Valid @RequestBody Ceiling body) {
        String s = session + "/" + year;
        jdbc.sql("SELECT registration.summer_set_ceiling(:s, :m, :r)").param("s", s).param("m", body.maxCourses(), Types.INTEGER)
                .param("r", body.reason() == null ? null : body.reason().trim(), Types.VARCHAR).query().listOfRows();
        return deskPeriod(s);
    }

    /** one tranche of the identification of the eligible (set-based: each student's category is read from the record, no result is
     *  read to decide it; the published results are counted for the figure of 'missing historical results'): the desk asks again until
     *  none is left; `since` is when this identification began (the students read since then are not read again). Run again in a
     *  fresh transaction on a passing clash with a payment */
    @PostMapping("/api/v1/summer/{session}/{year}/identify")
    @PreAuthorize(SETTERS)
    Map<String, Object> identify(@PathVariable String session, @PathVariable String year, @RequestBody(required = false) Identify body) {
        String s = session + "/" + year;
        String since = body == null || body.since() == null || body.since().isBlank() ? null : body.since();
        int limit = body == null || body.limit() == null ? 400 : Math.max(1, Math.min(body.limit(), 2000));
        return DeadlockRetry.inTransaction(tx, () -> {
            String started = since != null ? since : jdbc.sql("SELECT now()::text").query(String.class).single();
            String r = jdbc.sql("SELECT registration.summer_identify(:s, CAST(:since AS timestamptz), :l)::text")
                    .param("s", s).param("since", started).param("l", limit).query(String.class).single();
            Map<String, Object> out = new LinkedHashMap<>(json(r));
            // every student read has their published results counted (summer_candidate.results): the figure of this tranche
            out.putIfAbsent("results", out.get("read"));
            out.put("since", started);
            return out;
        });
    }

    /** the Summer's courses: each class, its lecturer, the students registered by the semester the course belongs to, the results */
    @GetMapping("/api/v1/summer/{session}/{year}/courses")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> courses(@PathVariable String session, @PathVariable String year) {
        String s = session + "/" + year;
        OfficeScope.Bound b = SummerAccess.readerBound(scope);   // V739: whatever office is active, a unit office is held to its unit (a sentinel when it resolves to nothing)
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

    /** V754: the Summer authorisations to look at again — one naming a course no longer on the catalogue (DEAD_CODE), one a one-off
     *  repair (V746, V751, V753) rewrote to another course than the trail from the grant gives (REWRITTEN); nothing is changed, the
     *  Office re-authorises */
    @GetMapping("/api/v1/summer/{session}/{year}/authorisations")
    @PreAuthorize(SETTERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> authorisations(@PathVariable String session, @PathVariable String year) {
        return jdbc.sql("SELECT * FROM registration.summer_authorisations_to_review(:s)").param("s", session + "/" + year).query().listOfRows();
    }

    /** the students told, once an event: the Summer open (every eligible student), closing (the eligible who have not paid), the
     *  examinations (every student registered for the Summer — V756: never a CCE or postgraduate third semester) — through the
     *  notification engine's templates, one message a student and channel. V779: in tranches walked by a cursor (about 19,000 students
     *  are eligible: one call would hold the request for minutes), each tranche its own request; the event key makes a repeat send nothing */
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
        int limit = body.limit() == null ? 500 : body.limit();
        Map<String, Object> r = json(jdbc.sql("SELECT registration.summer_tell(:s, :k, :l, CAST(:a AS uuid))::text").param("s", s).param("k", body.kind()).param("l", limit)
                .param("a", body.after() == null ? null : body.after().toString(), Types.VARCHAR).query(String.class).single());
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("kind", body.kind());
        out.put("told", r.get("told"));
        out.put("visited", r.get("visited"));
        out.put("next", r.get("next"));
        out.put("remaining", r.get("remaining"));
        return out;
    }

    /** V739: a paid Summer course the registration could not take, retried once what stopped it is put right */
    @PostMapping("/api/v1/summer/issues/{id}/retry")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> retry(@PathVariable UUID id) {
        return json(jdbc.sql("SELECT registration.summer_issue_retry(:id)::text").param("id", id).query(String.class).single());
    }

    /** the Summer's examination session opened, or its score sheets released to the lecturers (the existing examination engine).
     *  V779: the database's gate counts the paid courses not yet verified, live, and refuses while any stands
     *  (SUMMER_VERIFICATION_PENDING) or while the registration window is open (SUMMER_REGISTRATION_OPEN), whichever desk starts the
     *  act; this act does not reconcile first (a refusal would undo it): the desk's Reconcile is its own request, made before */
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
        return deskPeriod(s);
    }

    /** V779: why the examinations may go ahead although paid courses are not yet verified — a reason, recorded for the act, that
     *  holds only while the number unverified has not grown */
    @PostMapping("/api/v1/summer/{session}/{year}/exams/{act}/override")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> overrideGate(@PathVariable String session, @PathVariable String year, @PathVariable String act, @Valid @RequestBody GateOverride body) {
        String dbAct = switch (act) {
            case "open" -> "OPEN";
            case "release-sheets" -> "RELEASE";
            default -> throw new NotFound("examination act", act);
        };
        return json(jdbc.sql("SELECT registration.summer_exam_override_set(:s, :a, :r)::text").param("s", session + "/" + year).param("a", dbAct)
                .param("r", body.reason().trim()).query(String.class).single());
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
        // V739: unapplied Summer money (a reference confirmed after its charges were taken back or paid by another); V779: and the money
        // of a course the Academic Office found not outstanding or rejected after it was paid (source DECISION, with its course, the
        // state of its selection and the note the Bursar reads)
        out.put("credits", jdbc.sql("""
                SELECT c.id, c.session, c.amount, c.state, c.created_at, c.settled_at, c.settled_note, pr.reference, pr.receipt_no,
                       c.source, c.note, ch.course_code, ch.kind AS charge_kind, sel.state AS selection_state,
                       coalesce(st.matric_no, st.admission_no) AS number, st.surname || ', ' || st.other_names AS name
                  FROM registration.summer_credit c JOIN people.student st ON st.id = c.student_id
                  JOIN finance.payment_reference pr ON pr.id = c.reference_id
                  LEFT JOIN registration.summer_charge ch ON ch.id = c.source_charge_id
                  LEFT JOIN registration.summer_selection sel ON sel.student_id = c.student_id AND sel.session = c.session AND sel.course_code = ch.course_code
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
}
