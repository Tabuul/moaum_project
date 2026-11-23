package ng.edu.moaum.portal.siwes;

import java.math.BigDecimal;
import java.sql.Types;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.DecimalMin;
import jakarta.validation.constraints.Max;
import jakarta.validation.constraints.Min;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;

import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DeadlockRetry;
import ng.edu.moaum.portal.shared.NotFound;
import ng.edu.moaum.portal.shared.OfficeScope;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.AccessDeniedException;
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
 * V752 — SIWES registration at 300 Level, Second Semester (the University's master prompt of 12 November 2026). The rules are the
 * database's: who SIWES binds (registration.siwes_applies), why a student is not eligible (registration.siwes_eligibility), the fee in
 * force and the payment that settles it (finance.siwes_fee, finance.siwes_paid), the reference drawn once (finance.siwes_reference) and
 * the course registered once paid (registration.siwes_register). Here they are the student's doors, the Academic Office's desk and the
 * Bursary's. The fee is paid through the existing gateways (POST /api/v1/payments/checkout); paying does not register: the student
 * registers the course. Every write carries the request's X-Reason to the audit spine, as every write does.
 *
 * <p>V777 (the University's word of 22 November 2026, "yes charge every siwes course"): every SIWES course — a catalogue course the
 * Academic Office marks (catalogue.course.industrial_training) — carries the same fee, paid once a session before the student registers
 * it, whatever the programme, level or semester. The student's SIWES page then reads in one of two modes (see {@link #mine}): the
 * Second Semester SIWES binds, registered alone on the SIWES page as V752 made it, or any other SIWES course, paid here and registered
 * on Course Registration. The Bursary reads the students who hold a SIWES course with no SIWES payment (unpaidEntries).
 */
@RestController
class SiwesRegistrationController {

    /** who sets a session's SIWES — the period, the programmes, each programme's course (the database checks the office again) */
    private static final String SETTERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super')";
    private static final Set<String> SETTER_OFFICES = Set.of("academic", "registrar", "dregistrar", "super");
    /** who reads the desk: the setters, the Head of Department and the SIWES Coordinator (their department), the Dean and the Faculty
     *  Officer (their faculty), the Bursary, ICT, the Vice-Chancellor and the Deputy */
    private static final String READERS = "hasAnyAuthority('OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_super','OFFICE_hod',"
            + "'OFFICE_siwes','OFFICE_dean','OFFICE_facultyofficer','OFFICE_bursar','OFFICE_studentaccounts','OFFICE_ict','OFFICE_vc','OFFICE_dvc')";
    private static final Set<String> READER_OFFICES = Set.of("academic", "registrar", "dregistrar", "super", "hod", "siwes", "dean", "facultyofficer",
            "bursar", "studentaccounts", "ict", "vc", "dvc");
    /** who states the fee (a draft until published) and who publishes it: the Bursary, as the Summer's */
    private static final String FEE_SETTERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super')";
    private static final String FEE_PUBLISHERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_super')";
    /** who reads the fee: the offices that read Fee Setup (V648), the auditors among them */
    private static final String FEE_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit',"
            + "'OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_ict','OFFICE_admin','OFFICE_vc','OFFICE_dvc')";
    /** who reads the payments, each with its gateway reference and receipt (the Bursary's reconciliation) and the credits: the Bursary
     *  and the auditors */
    private static final String PAYMENT_READERS = "hasAnyAuthority('OFFICE_bursar','OFFICE_studentaccounts','OFFICE_super','OFFICE_audit','OFFICE_deputyaudit')";
    private static final Set<String> PAYMENT_READER_OFFICES = Set.of("bursar", "studentaccounts", "super", "audit", "deputyaudit");
    /** V777: who reads the students who hold a SIWES course with no SIWES payment — the offices that read the desk (a unit office its own
     *  unit's students), the Bursary's among them (the Bursar, Student Accounts, the Registrar and the Deputy Registrar, the Academic
     *  Office and the University's officers). The list is a tab of the desk, so its readers are the desk's readers: the auditors, who
     *  have no way into the desk, do not read it */
    private static final String UNPAID_READERS = READERS;
    private static final Set<String> UNPAID_READER_OFFICES = READER_OFFICES;
    private static final String SESSION = "^\\d{4}/\\d{4}$";
    private static final int PAGE_MAX = 500;

    private final JdbcClient jdbc;
    private final OfficeScope scope;
    /** V762's review (d62-1): the student's SIWES registration and the Bursar's settling or reopening of a credit take the student's SIWES
     *  lock before a payment's row; a write that locks the row first (the old fees reset, an upload, a gateway confirmation) can meet one in
     *  a deadlock, which PostgreSQL ends whole — the door runs again in a fresh transaction (DeadlockRetry) */
    private final TransactionTemplate tx;

    SiwesRegistrationController(JdbcClient jdbc, OfficeScope scope, PlatformTransactionManager transactions) {
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

    private static String blank(String s) {
        return s == null || s.isBlank() ? null : s.trim();
    }

    /** the session asked, else the University's current session */
    private String sessionOr(String asked) {
        String s = blank(asked);
        return s != null ? s : jdbc.sql("SELECT policy.university_current_session()").query(String.class).optional().orElse(null);
    }

    /** the unit the active office is held to. Authority is checked against every office the token carries, so a person who holds a
     *  reading office but acts in another would otherwise read the University: the active office must be one that reads (as V739 holds
     *  the Summer desk) */
    private OfficeScope.Bound bound(Set<String> readers, String what, String fac, String dept, String prog) {
        String o = office();
        if (o == null || !readers.contains(o)) {
            throw new AccessDeniedException(what + " is read in an office that reads it.");
        }
        return scope.bound(blank(fac), blank(dept), blank(prog));
    }

    private static boolean held(OfficeScope.Bound b) {
        return b.fac() != null || b.dept() != null || b.prog() != null;
    }

    /* ── the student's own ── */

    /** the student's SIWES of a session (the student's current session when none is named): eligibility and why not, the course, the
     *  period and its training dates, the fee, the payment, the open reference, the registration, and whether the Second Semester school
     *  fees are cleared (semesterFees, by the test registering applies: canRegister waits on them) — registration.siwes_eligibility as is.
     *  Beside it, the student's SIWES of every session (history: the payment that settled each session's fee and the SIWES registration,
     *  as the desk's detail lists them), so a student SIWES no longer binds reaches the session it was theirs; and, while courses stand
     *  in the SIWES course's way, how they leave (clearing: the student's drop door only while add and drop is open, the reset when the
     *  reset door allows it — as Course Registration offers them, K11).
     *  V777: every SIWES course carries the fee, so the answer reaches a student SIWES does not bind too, with the database's own keys
     *  passed through as they come: {@code mode} (SEMESTER — the Second Semester SIWES binds, the SIWES course registered alone on the SIWES
     *  page; COURSE — the student's programme carries a SIWES course at their level, or they hold or owe one: they pay here and register it on
     *  Course Registration beside their other courses; null — not asked), {@code bound} (SEMESTER's), {@code courses} (each SIWES course
     *  that is theirs: code, title, units, level, semester, basis, state, why — HELD, CARRYOVER or STRUCTURE — held, passed), and
     *  {@code registerOn} (SIWES_PAGE, COURSE_REGISTRATION or null). For COURSE the answer's level, semester, course and semesterFees are null,
     *  otherCourses is empty (each course in {@code courses} carries its own level and semester) and canRegister is false; canPay is the
     *  fee published and nothing paid. {@code clearing} is built for the SIWES semester alone, never for COURSE */
    @GetMapping("/api/v1/me/siwes")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional(readOnly = true)
    Map<String, Object> mine(Authentication auth, @RequestParam(required = false) String session) {
        UUID st = me(auth);
        Map<String, Object> out = new LinkedHashMap<>(json(jdbc.sql("SELECT registration.siwes_student_detail(:st, :s)::text").param("st", st)
                .param("s", blank(session), Types.VARCHAR).query(String.class).single()));
        // the desk's own words of who the student is: the student knows
        out.remove("matricNo");
        out.remove("name");
        // V777: only for the SIWES semester (applies: the Second Semester SIWES binds, the SIWES course alone). A student who registers the
        // SIWES course among their other courses (mode COURSE) has nothing in its way and no semester to clear here; the semester is the
        // answer's own (the Second Semester, the database's constant for the bound shape), not a literal of this door
        if (Boolean.TRUE.equals(out.get("applies")) && out.get("registration") == null && out.get("otherCourses") instanceof List<?> others && !others.isEmpty()
                && out.get("session") instanceof String s) {
            int sem = out.get("semester") instanceof Number n ? n.intValue() : 2;
            Map<String, Object> clearing = new LinkedHashMap<>();
            clearing.put("addDropOpen", Boolean.TRUE.equals(jdbc.sql("SELECT registration.add_drop_open(:st, :s, :sem)").param("st", st).param("s", s)
                    .param("sem", sem).query(Boolean.class).single()));
            // in a SIWES-bound Second Semester the reset door asks reset_refusal alone (StudentPortalService.registrationView, K11)
            String why = jdbc.sql("SELECT registration.reset_refusal(:st, :s, :sem, 'STUDENT_PORTAL')").param("st", st).param("s", s).param("sem", sem)
                    .query(String.class).optional().orElse(null);
            clearing.put("resetAllowed", why == null);
            clearing.put("resetWhy", why);
            out.put("clearing", clearing);
        }
        return out;
    }

    /** the reference for the SIWES registration fee of the student's current session: the open one, else one drawn at the published fee.
     *  The amount is the server's alone; the reference is then paid through the existing checkout */
    @PostMapping("/api/v1/me/siwes/reference")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    @Transactional
    Map<String, Object> reference(Authentication auth) {
        return json(jdbc.sql("SELECT finance.siwes_reference(:st)::text").param("st", me(auth)).query(String.class).single());
    }

    /** the SIWES course registered, once the fee is paid: approved as it is made; a second call returns the same. A student SIWES binds
     *  whose programme's course has ended or is unmapped waits on the Academic Office (422 SIWES_COURSE_MISSING) */
    @PostMapping("/api/v1/me/siwes/register")
    @PreAuthorize("hasAuthority('OFFICE_student')")
    Map<String, Object> register(Authentication auth) {
        UUID st = me(auth);
        return DeadlockRetry.inTransaction(tx, () -> json(jdbc.sql("SELECT registration.siwes_register(:st)::text").param("st", st).query(String.class).single()));
    }

    /* ── the Academic Office's desk ── */

    public record PeriodIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Pattern(regexp = "^(DRAFT|OPEN|CLOSED)$") String state,
                           LocalDate registrationOpens, LocalDate registrationCloses, LocalDate trainingStarts, LocalDate trainingEnds,
                           @Min(1) @Max(12) Integer durationMonths, @Size(max = 600) String note) {
    }

    public record ProgrammeIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotBlank @Size(max = 10) String programmeCode) {
    }

    /** a course code as long as the catalogue allows (ck_course_code: up to 20 characters; it was held to 16 here) */
    public record CourseIn(@NotBlank @Size(max = 10) String programmeCode, @Pattern(regexp = "^(?i)(CCMAS|BMAS)?$") String curriculum,
                           @Size(max = 20) String courseCode) {
    }

    /** V776: a catalogue course added to the SIWES courses (siwes true, the default) or taken off them */
    public record SiwesCourseIn(@NotBlank @Size(max = 20) String courseCode, Boolean siwes) {
    }

    /** a session's SIWES as the Academic Office configures it: the period, the programmes taking part (each with its SIWES course, for
     *  every curriculum its 300 Level students hold, the course's catalogue state — LIVE, or BOARD, SENATE or ENDED, which the desk
     *  warns of — and, V776, how the course is known: SET on the desk, or recognised in the programme's STRUCTURE or its DEPARTMENT
     *  and written down as the programme was added; where there is none, the course the catalogue now gives it (`found`) or the
     *  several it offers (`choices`)), the programmes that could, the SIWES courses of the catalogue (`siwesCourses`), the cohorts no
     *  live SIWES course reaches (`unreached`, with how many of them have paid or registered and so wait bound), the fee and the
     *  sessions. A department or faculty office reads its own programmes; `access` says what the acting office may do */
    @GetMapping("/api/v1/siwes/admin/config")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> config(@RequestParam(required = false) String session) {
        OfficeScope.Bound b = bound(READER_OFFICES, "SIWES registration", null, null, null);
        Map<String, Object> out = new LinkedHashMap<>(json(jdbc.sql("SELECT registration.siwes_config(:s)::text")
                .param("s", blank(session), Types.VARCHAR).query(String.class).single()));
        if (held(b)) {
            List<Object> own = new ArrayList<>();
            for (Object p : (List<?>) out.getOrDefault("programmes", List.of())) {
                Map<?, ?> m = (Map<?, ?>) p;
                if (same(b.fac(), m.get("facultyCode")) && same(b.dept(), m.get("departmentCode")) && same(b.prog(), m.get("code"))) own.add(p);
            }
            out.put("programmes", own);
            out.put("candidates", List.of());   // the setters (University offices) add programmes; a unit office reads its own
            // V776: the cohorts still waiting for a SIWES course, of its own programmes alone
            Set<String> mine = new java.util.HashSet<>();
            for (Object p : own) mine.add(String.valueOf(((Map<?, ?>) p).get("code")));
            List<Object> waiting = new ArrayList<>();
            for (Object u : (List<?>) out.getOrDefault("unreached", List.of())) {
                if (mine.contains(String.valueOf(((Map<?, ?>) u).get("programmeCode")))) waiting.add(u);
            }
            out.put("unreached", waiting);
            out.put("siwesCourses", ownSiwesCourses(out.get("siwesCourses"), own, waiting, mine));
        }
        // who last set the period, by name (the period's own JSON carries the office alone; set_by is a person's id, never shown)
        if (out.get("period") instanceof Map<?, ?> p && p.get("session") != null) {
            Map<String, Object> period = new LinkedHashMap<>();
            p.forEach((k, v) -> period.put(String.valueOf(k), v));
            period.put("setByName", jdbc.sql("SELECT finance.siwes_person_name(p.set_by) FROM registration.siwes_period p WHERE p.session = :s")
                    .param("s", String.valueOf(p.get("session"))).query(String.class).optional().orElse(null));
            out.put("period", period);
        }
        String o = office();
        out.put("access", Map.of("set", SETTER_OFFICES.contains(o), "read", true));
        return out;
    }

    private static boolean same(String bound, Object value) {
        return bound == null || bound.equalsIgnoreCase(String.valueOf(value));
    }

    /** V776: the SIWES courses a held office reads: those its own programmes carry, are set or written down for, or are offered — each
     *  with only its own programmes in programmes, setFor and attachmentFor (the other units' stay theirs). {@code own} is the office's
     *  programme rows (with their curricula), {@code waiting} its cohorts still without a course, {@code mine} their codes */
    private static List<Object> ownSiwesCourses(Object all, List<Object> own, List<Object> waiting, Set<String> mine) {
        Set<String> codes = new java.util.HashSet<>();
        List<Object> offers = new ArrayList<>(own);
        for (Object p : own) {
            Object curricula = ((Map<?, ?>) p).get("curricula");
            if (curricula instanceof List<?> cs) offers.addAll(cs);
        }
        offers.addAll(waiting);
        for (Object o : offers) {
            Map<?, ?> m = (Map<?, ?>) o;
            if (m.get("course") instanceof Map<?, ?> c && c.get("code") != null) codes.add(String.valueOf(c.get("code")));
            if (m.get("found") instanceof Map<?, ?> f && f.get("code") != null) codes.add(String.valueOf(f.get("code")));
            for (String key : List.of("choices", "elsewhere")) {
                if (m.get(key) instanceof List<?> l) {
                    for (Object x : l) if (x instanceof Map<?, ?> xm && xm.get("code") != null) codes.add(String.valueOf(xm.get("code")));
                }
            }
        }
        List<Object> kept = new ArrayList<>();
        if (!(all instanceof List<?> courses)) return kept;
        for (Object c : courses) {
            Map<?, ?> m = (Map<?, ?>) c;
            Map<String, Object> mine1 = new LinkedHashMap<>();
            m.forEach((k, v) -> mine1.put(String.valueOf(k), v));
            boolean carried = false;
            for (String key : List.of("programmes", "setFor", "attachmentFor")) {
                List<Object> own1 = new ArrayList<>();
                if (m.get(key) instanceof List<?> l) {
                    for (Object x : l) if (x instanceof Map<?, ?> xm && mine.contains(String.valueOf(xm.get("code")))) own1.add(x);
                }
                if (!own1.isEmpty()) carried = true;
                mine1.put(key, own1);
            }
            if (carried || codes.contains(String.valueOf(m.get("code")))) kept.add(mine1);
        }
        return kept;
    }

    /** the session's period: opened only with both windows dated (SIWES_PERIOD_DATES). V776: it opens whether or not every configured
     *  programme's SIWES course is known — a cohort no course reaches is not bound until one does, and the configuration lists it
     *  (`unreached`); each save recognises the course the catalogue now gives a programme still waiting */
    @PutMapping("/api/v1/siwes/admin/period")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> period(@Valid @RequestBody PeriodIn body) {
        return json(jdbc.sql("SELECT registration.siwes_set_period(:s, :st, :ro, :rc, :ts, :te, :d, :n)::text")
                .param("s", body.session()).param("st", body.state())
                .param("ro", body.registrationOpens(), Types.DATE).param("rc", body.registrationCloses(), Types.DATE)
                .param("ts", body.trainingStarts(), Types.DATE).param("te", body.trainingEnds(), Types.DATE)
                .param("d", body.durationMonths(), Types.INTEGER).param("n", blank(body.note()), Types.VARCHAR)
                .query(String.class).single());
    }

    /** a programme taking part in the session's SIWES. V776: added whether or not its SIWES course is known yet — the course is
     *  recognised from the catalogue as the programme is added (a SIWES course of the programme's 300 Level Second Semester structure,
     *  else its department's one; several of equal standing: none, never a guess) and written down as the programme's, so it stands as
     *  a course set on the desk does; or it is set afterwards (PUT courses) */
    @PostMapping("/api/v1/siwes/admin/programmes")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> addProgramme(@Valid @RequestBody ProgrammeIn body) {
        return json(jdbc.sql("SELECT registration.siwes_add_programme(:s, :p)::text").param("s", body.session()).param("p", body.programmeCode().trim())
                .query(String.class).single());
    }

    /** a programme taken out of a session's SIWES — never once a student of it has paid or registered (the database refuses) */
    @DeleteMapping("/api/v1/siwes/admin/programmes")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> removeProgramme(@RequestParam String session, @RequestParam String programmeCode) {
        return json(jdbc.sql("SELECT registration.siwes_remove_programme(:s, :p)::text").param("s", session.trim()).param("p", programmeCode.trim())
                .query(String.class).single());
    }

    /** a programme's SIWES course, for a curriculum or for every curriculum: an existing course of the catalogue (never one made here);
     *  no course takes the mapping away — never while students of the programme who paid or registered would be left with no SIWES
     *  course (422 SIWES_COURSE_IN_USE: the mapping is replaced by another course instead). Standing: a programme's course is never tied
     *  to a session; a student registered keeps the course the registration was made on */
    @PutMapping("/api/v1/siwes/admin/courses")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> course(@Valid @RequestBody CourseIn body) {
        return json(jdbc.sql("SELECT registration.siwes_set_course(:p, :c, :k)::text").param("p", body.programmeCode().trim())
                .param("c", blank(body.curriculum()), Types.VARCHAR).param("k", blank(body.courseCode()), Types.VARCHAR).query(String.class).single());
    }

    /** V776: an existing catalogue course added to the SIWES courses — the programmes still waiting for a course are recognised
     *  again — or taken off them (never one set as a programme's SIWES course, one students have paid or registered on, or one whose
     *  attachment semester students are registered in: 422 SIWES_COURSE_IN_USE; a row that only recognised it goes with it). Each
     *  department carries SIWES under its own code and title; a course whose title reads SIWES or Industrial Training is marked by the
     *  catalogue as it is added. Answers the list */
    @PutMapping("/api/v1/siwes/admin/siwes-courses")
    @PreAuthorize(SETTERS)
    @Transactional
    Map<String, Object> siwesCourse(@Valid @RequestBody SiwesCourseIn body) {
        return json(jdbc.sql("SELECT jsonb_build_object('siwesCourses', registration.siwes_mark_course(:k, :on))::text")
                .param("k", body.courseCode().trim()).param("on", body.siwes() == null || body.siwes(), Types.BOOLEAN).query(String.class).single());
    }

    /** the students of a session's SIWES — eligible, paid, registered — filtered by unit, status and a search, a page at a time; a unit
     *  office is held to its unit whatever is asked */
    @GetMapping("/api/v1/siwes/admin/students")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> students(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                                 @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                                 @RequestParam(required = false) String status, @RequestParam(required = false) String q,
                                 @RequestParam(defaultValue = "0") int page, @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = bound(READER_OFFICES, "SIWES registration", faculty, department, programme);
        String s = sessionOr(session);
        int sz = Math.max(1, Math.min(size, PAGE_MAX));
        int pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM registration.siwes_students(:s, :f, :d, :p, :st, :q, :n, :off)")
                .param("s", s, Types.VARCHAR).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("st", blank(status), Types.VARCHAR).param("q", blank(q), Types.VARCHAR).param("n", sz).param("off", pg * sz)
                .query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", rows.isEmpty() ? 0L : ((Number) rows.get(0).get("total")).longValue());
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows.stream().map(SiwesRegistrationController::studentRow).toList());
        return out;
    }

    private static Map<String, Object> studentRow(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("studentId", r.get("student_id"));
        m.put("matricNo", r.get("matric_no"));
        m.put("name", r.get("name"));
        m.put("programmeCode", r.get("programme_code"));
        m.put("programme", r.get("programme"));
        m.put("departmentCode", r.get("dept_code"));
        m.put("department", r.get("department"));
        m.put("facultyCode", r.get("faculty_code"));
        m.put("faculty", r.get("faculty"));
        m.put("level", r.get("level"));
        m.put("curriculum", r.get("curriculum"));
        m.put("eligible", r.get("eligible"));
        m.put("reasons", r.get("reasons"));
        m.put("paid", r.get("paid"));
        m.put("paymentSource", r.get("payment_source"));
        m.put("paymentReference", r.get("payment_reference"));
        m.put("receiptNo", r.get("receipt_no"));
        m.put("paidAt", r.get("paid_at"));
        m.put("amount", r.get("amount"));
        m.put("registered", r.get("registered"));
        m.put("registeredAt", r.get("registered_at"));
        m.put("registrationStatus", r.get("registration_status"));
        // the course registered, else the programme's SIWES course the student would register
        m.put("courseCode", r.get("registered_course") != null ? r.get("registered_course") : r.get("course_code"));
        return m;
    }

    /** one student's SIWES of a session, and every session's SIWES payment and registration — within the office's unit */
    @GetMapping("/api/v1/siwes/admin/students/{studentId}")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> student(@PathVariable UUID studentId, @RequestParam(required = false) String session) {
        Map<String, Object> unit = jdbc.sql("""
                SELECT s.programme_code AS prog, d.code AS dept, coalesce(d.faculty_code, p.faculty_code) AS fac
                  FROM people.student s LEFT JOIN ref.programme p ON p.code = s.programme_code LEFT JOIN ref.department d ON d.code = p.dept_code
                 WHERE s.id = :id
                """).param("id", studentId).query().listOfRows().stream().findFirst().orElseThrow(() -> new NotFound("student", studentId));
        bound(READER_OFFICES, "SIWES registration", (String) unit.get("fac"), (String) unit.get("dept"), (String) unit.get("prog"));
        return json(jdbc.sql("SELECT registration.siwes_student_detail(:id, :s)::text").param("id", studentId).param("s", sessionOr(session), Types.VARCHAR)
                .query(String.class).single());
    }

    /** the figures: eligible, paid, registered, yet to pay, yet to register, the money paid and outstanding — and by faculty, department
     *  and programme */
    @GetMapping("/api/v1/siwes/admin/stats")
    @PreAuthorize(READERS)
    @Transactional(readOnly = true)
    Map<String, Object> stats(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                              @RequestParam(required = false) String department, @RequestParam(required = false) String programme) {
        OfficeScope.Bound b = bound(READER_OFFICES, "SIWES registration", faculty, department, programme);
        return json(jdbc.sql("SELECT registration.siwes_stats(:s, :f, :d, :p)::text").param("s", sessionOr(session), Types.VARCHAR)
                .param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR).query(String.class).single());
    }

    /** V777 (decision 2 of 22 November 2026: the students who registered a SIWES course before the rule, with no SIWES payment, are
     *  asked to pay): the SIWES courses that stand on a registration of the session — every one not dropped or withdrawn — of a student the
     *  fee is asked of (an undergraduate in study, not CCE) who has no SIWES payment standing for the session (registration.siwes_entries_unpaid:
     *  the portal's or the old portal's, of either semester, settles it). A row is a student and a course; a student with two SIWES courses
     *  is listed twice and owes the fee once. {@code payable} says the SIWES page asks them now. Read-only, a page at a time, read by the
     *  desk's readers and held to the unit of a department or faculty office (the Head of Department and the SIWES Coordinator their
     *  department, the Dean and the Faculty Officer their faculty) whatever is asked, as the desk's student list is; {@code students} counts the
     *  students of the whole selection (not the page), {@code fee} is the fee in force for the session (null while none is published) */
    @GetMapping("/api/v1/siwes/admin/unpaid-entries")
    @PreAuthorize(UNPAID_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> unpaidEntries(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                                      @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                                      @RequestParam(required = false) String q, @RequestParam(defaultValue = "0") int page,
                                      @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = bound(UNPAID_READER_OFFICES, "The SIWES courses held with no SIWES payment", faculty, department, programme);
        String s = sessionOr(session);
        int sz = Math.max(1, Math.min(size, PAGE_MAX));
        int pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("""
                WITH x AS (
                    SELECT u.*, d.code AS dept_code, d.name AS department, coalesce(d.faculty_code, p.faculty_code) AS faculty_code, f.name AS faculty
                      FROM registration.siwes_entries_unpaid(CAST(:s AS text)) u
                      LEFT JOIN ref.programme p ON p.code = u.programme_code
                      LEFT JOIN ref.department d ON d.code = p.dept_code
                      LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
                     WHERE (CAST(:f AS text) IS NULL OR coalesce(d.faculty_code, p.faculty_code) = btrim(CAST(:f AS text)))
                       AND (CAST(:d AS text) IS NULL OR d.code = btrim(CAST(:d AS text)))
                       AND (CAST(:p AS text) IS NULL OR u.programme_code = upper(btrim(CAST(:p AS text))))
                       AND (CAST(:q AS text) IS NULL OR u.name ILIKE '%' || btrim(CAST(:q AS text)) || '%'
                            OR coalesce(u.matric_no, '') ILIKE '%' || btrim(CAST(:q AS text)) || '%'))
                SELECT x.*, count(*) OVER () AS total, (SELECT count(DISTINCT y.student_id) FROM x y) AS students
                  FROM x
                 ORDER BY x.faculty, x.department, x.programme, x.name, x.student_id, x.semester, x.course_code
                 LIMIT :n OFFSET :off
                """)
                .param("s", s, Types.VARCHAR).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("q", blank(q), Types.VARCHAR).param("n", sz).param("off", pg * sz).query().listOfRows();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("total", rows.isEmpty() ? 0L : ((Number) rows.get(0).get("total")).longValue());
        out.put("students", rows.isEmpty() ? 0L : ((Number) rows.get(0).get("students")).longValue());
        out.put("fee", s == null ? null : jdbc.sql("SELECT finance.siwes_fee_for(CAST(:s AS text))").param("s", s, Types.VARCHAR).query(BigDecimal.class).optional().orElse(null));
        out.put("page", pg);
        out.put("size", sz);
        out.put("rows", rows.stream().map(SiwesRegistrationController::unpaidRow).toList());
        return out;
    }

    private static Map<String, Object> unpaidRow(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("studentId", r.get("student_id"));
        m.put("matricNo", r.get("matric_no"));
        m.put("name", r.get("name"));
        m.put("programmeCode", r.get("programme_code"));
        m.put("programme", r.get("programme"));
        m.put("departmentCode", r.get("dept_code"));
        m.put("department", r.get("department"));
        m.put("facultyCode", r.get("faculty_code"));
        m.put("faculty", r.get("faculty"));
        m.put("currentLevel", r.get("current_level"));   // the student's level now
        m.put("courseCode", r.get("course_code"));
        m.put("courseTitle", r.get("course_title"));
        m.put("level", r.get("level"));                  // the level and semester of the registration the course stands on
        m.put("semester", r.get("semester"));
        m.put("registrationStatus", r.get("registration_status"));
        m.put("payable", Boolean.TRUE.equals(r.get("payable")));
        return m;
    }

    /* ── the Bursary's ── */

    public record FeeIn(@NotBlank @Pattern(regexp = SESSION) String session, @NotNull @DecimalMin(value = "1") BigDecimal amount,
                        @Size(max = 600) String note) {
    }

    public record ForSession(@NotBlank @Pattern(regexp = SESSION) String session) {
    }

    public record Settle(@NotBlank @Pattern(regexp = "^(APPLIED|REFUNDED)$") String state, @NotBlank @Size(min = 10, max = 600) String note) {
    }

    /** the SIWES registration fee of a session: the figure in force and its state (a fee never published is its draft, never charged),
     *  who published it, the draft waiting for the Bursar (null when none) and every statement and publication — finance.siwes_fee_view */
    @GetMapping("/api/v1/finance/siwes/fee")
    @PreAuthorize(FEE_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> fee(@RequestParam(required = false) String session) {
        return json(jdbc.sql("SELECT finance.siwes_fee_view(:s)::text").param("s", sessionOr(session), Types.VARCHAR).query(String.class).single());
    }

    /** the fee stated: a draft beside the published fee, which stays in force until the Bursar publishes the draft — Student Accounts
     *  states, never withdraws (V752's review); a reference already drawn keeps the figure it was drawn at */
    @PutMapping("/api/v1/finance/siwes/fee")
    @PreAuthorize(FEE_SETTERS)
    @Transactional
    Map<String, Object> stateFee(@Valid @RequestBody FeeIn body) {
        return json(jdbc.sql("SELECT finance.siwes_fee_state(:s, :a, :n)::text").param("s", body.session()).param("a", body.amount())
                .param("n", blank(body.note()), Types.VARCHAR).query(String.class).single());
    }

    /** the draft put in force (it replaces the published figure, which stays in the history) and cleared */
    @PostMapping("/api/v1/finance/siwes/fee/publish")
    @PreAuthorize(FEE_PUBLISHERS)
    @Transactional
    Map<String, Object> publishFee(@Valid @RequestBody ForSession body) {
        return json(jdbc.sql("SELECT finance.siwes_fee_publish(:s)::text").param("s", body.session()).query(String.class).single());
    }

    /** the confirmed SIWES payments — the portal's and the old portal's — each with the gateway's own reference, the receipt, whether
     *  it settles the student's fee or stands as a credit and what was given back on it; never a school-fee or GST payment. The totals
     *  are the database's, over every payment the filters select (not the page): the screen's tiles and its export read them, never a
     *  sum of their own that could disagree. Each row says whether the payment waits on the Bursary's bank check (V561), as the credits
     *  list says it: bankCheck, the database's words, and bankCheckState, its code (K31, below); both absent when it waits on nothing,
     *  and on a payment given back (its credit refunded, or refunded on the refund desk with no credit: K35, the credits list's rule),
     *  whose hold would say "not refunded or moved" beside the money already refunded */
    @GetMapping("/api/v1/finance/siwes/payments")
    @PreAuthorize(PAYMENT_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> payments(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                                 @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                                 @RequestParam(required = false) String source, @RequestParam(defaultValue = "0") int page,
                                 @RequestParam(defaultValue = "50") int size) {
        OfficeScope.Bound b = bound(PAYMENT_READER_OFFICES, "The SIWES payments", faculty, department, programme);
        String s = sessionOr(session);
        int sz = Math.max(1, Math.min(size, PAGE_MAX));
        int pg = Math.max(0, page);
        List<Map<String, Object>> rows = jdbc.sql("SELECT * FROM finance.siwes_payments(:s, :f, :d, :p, :src, :n, :off)")
                .param("s", s, Types.VARCHAR).param("f", b.fac(), Types.VARCHAR).param("d", b.dept(), Types.VARCHAR).param("p", b.prog(), Types.VARCHAR)
                .param("src", blank(source), Types.VARCHAR).param("n", sz).param("off", pg * sz).query().listOfRows();
        List<Map<String, Object>> out = new ArrayList<>();
        for (Map<String, Object> r : rows) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("reference", r.get("reference"));
            m.put("studentId", r.get("student_id"));
            m.put("matricNo", r.get("matric_no"));
            m.put("name", r.get("name"));
            m.put("programmeCode", r.get("programme_code"));
            m.put("programme", r.get("programme"));
            m.put("departmentCode", r.get("dept_code"));
            m.put("department", r.get("department"));
            m.put("facultyCode", r.get("faculty_code"));
            m.put("faculty", r.get("faculty"));
            m.put("session", r.get("session"));
            m.put("amount", r.get("amount"));
            m.put("gateway", r.get("gateway"));
            m.put("gatewayReference", r.get("gateway_reference"));
            m.put("receiptNo", r.get("receipt_no"));
            m.put("confirmedAt", r.get("confirmed_at"));
            m.put("source", r.get("source"));
            m.put("settles", r.get("settles"));
            m.put("creditState", r.get("credit_state"));
            m.put("refunded", r.get("refunded"));
            m.put("bankCheck", r.get("bank_check"));
            m.put("bankCheckState", r.get("bank_check_state"));
            out.add(m);
        }
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("session", s);
        body.put("total", rows.isEmpty() ? 0L : ((Number) rows.get(0).get("total")).longValue());
        // amount = amountSettling + amountRefunded + amountCredits, each payment counted once: what settles students' fees, what was
        // given back (the refund desk's refunds, credits the Bursar recorded refunded), and the money held that settles nothing (open or
        // applied credits, an old-portal payment made twice)
        body.put("amount", rows.isEmpty() ? BigDecimal.ZERO : rows.get(0).get("total_amount"));
        body.put("amountSettling", rows.isEmpty() ? BigDecimal.ZERO : rows.get(0).get("total_settling"));
        body.put("amountRefunded", rows.isEmpty() ? BigDecimal.ZERO : rows.get(0).get("total_refunded"));
        body.put("amountCredits", rows.isEmpty() ? BigDecimal.ZERO : rows.get(0).get("total_credits"));
        body.put("page", pg);
        body.put("size", sz);
        body.put("rows", out);
        return body;
    }

    /** SIWES money received for a session already paid (a second reference paid at a bank, after the card or the old portal had paid):
     *  never applied twice, held as a credit for the Bursar. A credit whose payment is archived for review, or no longer confirmed, is
     *  not listed until the payment stands again. Each row as the screens read it (K6'): why the credit arose (reason) apart from how it
     *  was settled (note); whether the database settled it itself (automatic: a move, the fee settled in another payment's absence, the
     *  refund desk) and whether its payment now settles the fee (settles); and canRefund and canReopen, the very tests the settle and
     *  reopen below apply, so the screens offer only what the database will do. bankCheck, the database's words, when the credit's
     *  payment waits on the Bursary's bank check (V561's standing rule: an old-portal payment that may be a bank double charge — another of
     *  the same student, session, item, day and amount under another payment number — is refunded only once the bank check on Old Fees
     *  History finds it received) — an open credit, or one that settles the fee meanwhile; absent otherwise. bankCheckState is the
     *  database's code for that wait (K31, finance.siwes_bank_hold), passed through as it comes, never read from the words: PROPOSED (a
     *  withdrawal as never received of a record of its day waits for the second Bursary officer), NOT_RECEIVED (the bank check found this
     *  very record never received), NOT_RECEIVED_WAITING (the check found another record of its day never received; this one, received,
     *  waits until that one is withdrawn), UNCHECKED (a possible bank double charge not yet checked). A credit on a record found never
     *  received is not listed (K27: that record does not stand); found received after all, it is listed again. settledKind, how the
     *  credit was settled, as the database recorded it (SETTLES, MOVED, DESK_REFUND, HAND_REFUND; null while open) — never read back from
     *  the note, which is free text */
    @GetMapping("/api/v1/finance/siwes/credits")
    @PreAuthorize(PAYMENT_READERS)
    @Transactional(readOnly = true)
    List<Map<String, Object>> credits(@RequestParam(required = false) String session) {
        bound(PAYMENT_READER_OFFICES, "The SIWES credits", null, null, null);
        return jdbc.sql("SELECT * FROM finance.siwes_credits(:s)").param("s", blank(session), Types.VARCHAR).query().listOfRows()
                .stream().map(SiwesRegistrationController::creditRow).toList();
    }

    private static Map<String, Object> creditRow(Map<String, Object> r) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("id", r.get("id"));
        m.put("studentId", r.get("student_id"));
        m.put("student", r.get("name"));
        m.put("matric", r.get("matric_no"));
        m.put("session", r.get("session"));
        m.put("reference", r.get("reference"));
        m.put("amount", r.get("amount"));
        m.put("state", r.get("state"));
        m.put("reason", r.get("reason"));
        m.put("note", r.get("settled_note"));
        m.put("createdAt", r.get("created_at"));
        m.put("paidAt", r.get("paid_at"));
        m.put("settledAt", r.get("settled_at"));
        m.put("settledByName", r.get("settled_by_name"));
        m.put("automatic", Boolean.TRUE.equals(r.get("automatic")));
        m.put("settles", Boolean.TRUE.equals(r.get("settles")));
        m.put("canRefund", Boolean.TRUE.equals(r.get("can_refund")));
        m.put("canReopen", Boolean.TRUE.equals(r.get("can_reopen")));
        m.put("bankCheck", r.get("bank_check"));
        m.put("bankCheckState", r.get("bank_check_state"));
        m.put("settledKind", r.get("settled_kind"));
        return m;
    }

    /** a credit settled by the Bursar with a note; the money itself is moved on the desks that move money. As the Summer's (V742, V751)
     *  the database refuses, each a 422 with its code (finance.siwes_credit_refusal, which the list's canRefund reads): a credit no
     *  longer open (SIWES_CREDIT_UNKNOWN); one whose payment is archived for review, unconfirmed or no longer the credit's SIWES payment
     *  (SIWES_CREDIT_HELD); "Applied" by hand, for a SIWES credit is the whole of its payment and is applied by moving the payment on the
     *  payment correction desk (SIWES_CREDIT_MOVE_IT); one whose payment a refund on the refund desk stands against, which the desk gives
     *  back and whose approval settles the credit (SIWES_CREDIT_REFUND_DESK); and the payment that now settles the student's fee, or that
     *  a standing SIWES registration was made on (SIWES_CREDIT_SETTLES); and an old-portal payment that may be a bank double charge until
     *  the Bursary's bank check finds it received (SIWES_CREDIT_CHECK_BANK). The refund desk refuses the other way round
     *  (REFUND_SIWES_CREDIT_SETTLED), so one payment is never given back twice, refunds a SIWES payment whole or not at all
     *  (REFUND_SIWES_PART, on raising and on approval: the fee is all or nothing) and once (REFUND_SIWES_GIVEN_BACK, V762: a second refund
     *  raised or approved on it, or more than is left on it — the desk and this hand refund wait on the student's SIWES lock, so two at one
     *  moment, a double submit or two officers, are decided one after the other) and refunds neither payment of a possible bank double
     *  charge before that check (REFUND_SIWES_CHECK_BANK) — nor does the payment correction desk move one (REALLOC_SIWES_CHECK_BANK) —
     *  and a check that found a record of the day never received holds every SIWES payment of that day until the record is withdrawn.
     *  The withdrawal of a SIWES payment as never received is refused while a standing SIWES registration rests on it alone
     *  (PAY_NOT_RECEIVED_SIWES_REGISTERED, on Old Fees History), and once its credit was refunded, by the Bursar's hand or on the refund
     *  desk (PAY_NOT_RECEIVED_SIWES_REFUNDED, K26: raised on its own or named by a bank check, which is then refused whole). Each reaches
     *  the caller as 422 with its code, the database's words as the detail and its HINT as the remedy, through ProblemHandler, as every
     *  "CODE: words" refusal of the database does */
    @PostMapping("/api/v1/finance/siwes/credits/{id}/settle")
    @PreAuthorize(FEE_PUBLISHERS)
    Map<String, Object> settle(@PathVariable UUID id, @Valid @RequestBody Settle body) {
        return DeadlockRetry.inTransaction(tx, () -> json(jdbc.sql("SELECT finance.siwes_credit_settle(:id, :st, :n)::text").param("id", id)
                .param("st", body.state()).param("n", body.note().trim()).query(String.class).single()));
    }

    public record Reopen(@NotBlank @Size(min = 10, max = 600) String reason) {
    }

    /** a credit the Bursar settled by hand in error reopened, with a reason on the audit trail (as the Summer's, V751), while its payment
     *  stands as the credit's SIWES payment; one a move, the fee settled or the refund desk settled follows its payment and is never
     *  reopened by hand (SIWES_CREDIT_NOT_REOPENED; finance.siwes_credit_reopen_refusal, which the list's canReopen reads). The one
     *  rule is then applied again to the student's session (K33): where nothing else settles the fee by then (the payment that settled
     *  it given back, moved or archived meanwhile), the reopened credit settles it. The answer is the credit as it then stands, in the
     *  database's names: state OPEN, or APPLIED with settled_kind SETTLES — never a fee paid by an open credit offered for refund */
    @PostMapping("/api/v1/finance/siwes/credits/{id}/reopen")
    @PreAuthorize(FEE_PUBLISHERS)
    Map<String, Object> reopen(@PathVariable UUID id, @Valid @RequestBody Reopen body) {
        return DeadlockRetry.inTransaction(tx, () -> json(jdbc.sql("SELECT finance.siwes_credit_reopen(:id, :r)::text").param("id", id)
                .param("r", body.reason().trim()).query(String.class).single()));
    }

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** a jsonb the database built, as a map the response carries */
    private static Map<String, Object> json(String text) {
        if (text == null) {
            return new LinkedHashMap<>();
        }
        return JSON.readValue(text, new tools.jackson.core.type.TypeReference<Map<String, Object>>() { });
    }
}
