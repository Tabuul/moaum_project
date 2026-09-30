package ng.edu.moaum.portal.platform;

import java.sql.Types;
import java.time.OffsetDateTime;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

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

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;
import jakarta.validation.constraints.Size;
import ng.edu.moaum.portal.shared.AuditContext;
import ng.edu.moaum.portal.shared.AuditContextHolder;
import ng.edu.moaum.portal.shared.DomainRuleViolation;

/**
 * The portal's windows (V288): whether school fees payment and course registration are open, closed,
 * scheduled or in their late period — read by every desk that needs to know, changed by the Director
 * of ICT alone. The Director controls availability; the Bursary and the Academic Office keep every
 * financial and academic rule. Each act supersedes the rule before it and writes its event, so the
 * history is never lost; the students of the session are told when a window opens, reopens, is
 * extended or closes.
 *
 * <p>V295 adds a third window, ADMISSION_STATUS_CHECKING: whether every applicant with a valid Post-UTME application of a
 * session may pay the admission checking fee and check their admission status. It runs over the whole admission exercise (no
 * semester, no late period), is closed until the Director first opens it, and its opening, extension and closing are told to
 * the session's applicants; its counts and report are read by the Director and the admissions offices.
 */
@RestController
@RequestMapping("/api/v1/portal-windows")
class PortalWindowController {

    /** the one office that opens and closes the portal's windows */
    private static final String DIRECTOR = "hasAuthority('OFFICE_ict')";
    private static final List<String> TYPES = List.of("SCHOOL_FEES_PAYMENT", "COURSE_REGISTRATION");
    /** V295: admission status checking, a window of the admission exercise, beside the two of the academic session */
    private static final String CHECKING = "ADMISSION_STATUS_CHECKING";
    /** who reads admission status checking's counts and report: the Director, and the offices that read admissions */
    private static final String CHECKING_READERS =
            "hasAnyAuthority('OFFICE_ict','OFFICE_academic','OFFICE_registrar','OFFICE_dregistrar','OFFICE_admin','OFFICE_super')";

    private final JdbcClient jdbc;

    PortalWindowController(JdbcClient jdbc) {
        this.jdbc = jdbc;
    }

    /** the windows of a session: the session-wide rule and each semester's, their states now, the students they reach, the last acts */
    @GetMapping
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    Map<String, Object> read(@RequestParam(required = false) String session) {
        String s = session == null || session.isBlank()
                ? jdbc.sql("SELECT coalesce((SELECT name FROM policy.academic_session WHERE state = 'CURRENT'), (SELECT max(name) FROM policy.academic_session WHERE state <> 'PLANNED'), (SELECT max(name) FROM policy.academic_session))").query(String.class).single()
                : session.trim();
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", jdbc.sql("SELECT name, state FROM policy.academic_session ORDER BY name DESC").query().listOfRows());
        out.put("semesters", jdbc.sql("SELECT number, state, registration_opens, registration_closes, late_registration_closes, fresh_registration_from FROM policy.semester WHERE session = :s ORDER BY number").param("s", s).query().listOfRows());
        out.put("openSemester", jdbc.sql("SELECT coalesce(max(number), 1) FROM policy.semester WHERE session = :s AND state = 'OPEN'").param("s", s).query(Integer.class).single());
        List<Map<String, Object>> windows = new java.util.ArrayList<>();
        for (String t : TYPES) {
            for (Integer sem : java.util.Arrays.asList(null, 1, 2, 3)) {
                Map<String, Object> w = new LinkedHashMap<>(state(t, s, sem));
                w.put("type", t);
                w.put("scope", sem == null ? "SESSION" : "SEMESTER");
                w.put("semesterAsked", sem);
                windows.add(w);
            }
        }
        out.put("windows", windows);
        out.put("affected", jdbc.sql("""
                SELECT count(*) FROM people.student st
                 WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                   AND (st.entry_session = :s OR EXISTS (SELECT 1 FROM registration.course_registration r WHERE r.student_id = st.id AND r.session = :s)
                        OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = st.id AND p.session = :s))
                """).param("s", s).query(Long.class).single());
        out.put("lateFees", jdbc.sql("SELECT kind, count(*) AS lines, sum(amount) AS total FROM finance.fee_schedule WHERE session = :s AND ended_at IS NULL AND kind <> 'FEE' GROUP BY kind ORDER BY kind").param("s", s).query().listOfRows());
        out.put("events", history(s, null, 100));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    @GetMapping("/history")
    @PreAuthorize(DIRECTOR)
    @Transactional(readOnly = true)
    Map<String, Object> historyOf(@RequestParam(required = false) String session, @RequestParam(required = false) String type) {
        return Map.of("events", history(session, type, 1000));
    }

    public record ActIn(@NotBlank String session, Integer semester,
                        @NotBlank @Pattern(regexp = "OPEN|CLOSE|REOPEN|SCHEDULE|EXTEND|SHORTEN|EDIT") String action,
                        OffsetDateTime opensAt, OffsetDateTime closesAt, OffsetDateTime lateUntil, Boolean lateFeeEnabled,
                        @Size(max = 600) String reason) {
    }

    /** one act on one window; the students of the session are told when it opens, reopens, is extended or closes */
    @PostMapping("/{type}")
    @PreAuthorize(DIRECTOR)
    @Transactional
    Map<String, Object> act(@PathVariable String type, @Valid @RequestBody ActIn body) {
        String t = type.trim().toUpperCase();
        if (!TYPES.contains(t) && !CHECKING.equals(t)) {
            throw new DomainRuleViolation("WINDOW_TYPE", "The portal's windows are school fees payment, course registration and admission status checking.", new DomainRuleViolation.Remedy("Name one of the three.", "Directorate of ICT"));
        }
        if (CHECKING.equals(t) && (body.semester() != null || body.lateUntil() != null || Boolean.TRUE.equals(body.lateFeeEnabled()))) {
            throw new DomainRuleViolation("WINDOW_CHECKING_SESSION", "Admission status checking opens and closes for the whole admission exercise of a session, with no semester and no late period.",
                    new DomainRuleViolation.Remedy("Leave the semester and the late period blank.", "Directorate of ICT"));
        }
        if (body.semester() != null && (body.semester() < 1 || body.semester() > 3)) {
            throw new DomainRuleViolation("WINDOW_SEMESTER", "A semester is 1, 2 or 3, or blank for the whole session.", new DomainRuleViolation.Remedy("Choose the semester or leave it blank.", "Directorate of ICT"));
        }
        Map<String, Object> before = state(t, body.session(), body.semester());
        AuditContext ctx = AuditContextHolder.required();
        UUID id = jdbc.sql("SELECT policy.window_act(:t, :s, :sem, :a, :o, :c, :l, :fee, :r, :by, :office)")
                .param("t", t).param("s", body.session().trim()).param("sem", body.semester(), Types.INTEGER).param("a", body.action())
                .param("o", body.opensAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("c", body.closesAt(), Types.TIMESTAMP_WITH_TIMEZONE).param("l", body.lateUntil(), Types.TIMESTAMP_WITH_TIMEZONE)
                .param("fee", body.lateFeeEnabled(), Types.BOOLEAN).param("r", body.reason(), Types.VARCHAR).param("by", ctx.actorId(), Types.OTHER).param("office", ctx.actorOffice(), Types.VARCHAR)
                .query(UUID.class).single();
        Map<String, Object> after = state(t, body.session(), body.semester());
        int told = 0;
        if (List.of("OPEN", "REOPEN", "EXTEND", "CLOSE").contains(body.action()) && !String.valueOf(before.get("state")).equals(String.valueOf(after.get("state"))) || "EXTEND".equals(body.action())) {
            told = CHECKING.equals(t)
                    ? jdbc.sql("SELECT admissions.tell_status_checking(:s, :a)").param("s", body.session().trim()).param("a", body.action()).query(Integer.class).single()
                    : tell(t, body.session().trim(), body.semester(), body.action(), after);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("windowId", id);
        out.put("before", before);
        out.put("after", after);
        out.put("told", told);
        out.putAll(CHECKING.equals(t) ? checking(body.session()) : read(body.session()));
        return out;
    }

    /* ── admission status checking (V295): the window of the admission exercise, its counts, its report ── */

    /** the admission session the desk opens on: the latest with applications that is on the calendar, else the current one */
    private String admissionSession(String asked) {
        if (asked != null && !asked.isBlank()) return asked.trim();
        return jdbc.sql("""
                SELECT coalesce(
                    (SELECT a.session FROM admissions.application a JOIN policy.academic_session s ON s.name = a.session
                      WHERE s.state IN ('DRAFT', 'PLANNED', 'CURRENT') GROUP BY a.session ORDER BY max(a.created_at) DESC LIMIT 1),
                    (SELECT name FROM policy.academic_session WHERE state = 'CURRENT'),
                    (SELECT max(name) FROM policy.academic_session))
                """).query(String.class).single();
    }

    /** the window of a session's admission exercise, what it reaches, and its history */
    @GetMapping("/admission-checking")
    @PreAuthorize(CHECKING_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> checking(@RequestParam(required = false) String session) {
        String s = admissionSession(session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("sessions", jdbc.sql("""
                SELECT s.name, s.state, (SELECT count(*) FROM admissions.application a WHERE a.session = s.name) AS applicants
                  FROM policy.academic_session s ORDER BY s.name DESC
                """).query().listOfRows());
        Map<String, Object> w = new LinkedHashMap<>(state(CHECKING, s, null));
        w.put("type", CHECKING);
        out.put("window", w);
        out.put("summary", jdbc.sql("SELECT * FROM admissions.status_checking_summary(:s)").param("s", s).query().singleRow());
        out.put("fee", jdbc.sql("SELECT f.checking_fee, f.stated FROM admissions.applicant_fee_rule(:s) f").param("s", s).query().listOfRows().stream().findFirst().orElse(null));
        out.put("events", history(s, CHECKING, 200));
        out.put("now", OffsetDateTime.now());
        return out;
    }

    /** every application of the session with its checking fee, its checks and its authoritative result, filtered */
    @GetMapping("/admission-checking/report")
    @PreAuthorize(CHECKING_READERS)
    @Transactional(readOnly = true)
    Map<String, Object> checkingReport(@RequestParam(required = false) String session, @RequestParam(required = false) String faculty,
                                       @RequestParam(required = false) String department, @RequestParam(required = false) String programme,
                                       @RequestParam(required = false) String sex, @RequestParam(required = false) String payment,
                                       @RequestParam(required = false) String result, @RequestParam(required = false) String checked,
                                       @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to) {
        String s = admissionSession(session);
        String where = """
                 WHERE (:fac::text IS NULL OR r.faculty_code = :fac) AND (:dept::text IS NULL OR r.dept_code = :dept)
                   AND (:prog::text IS NULL OR r.programme_code = :prog) AND (:sex::text IS NULL OR upper(left(coalesce(r.sex, ''), 1)) = :sex)
                   AND (:pay::text IS NULL OR (:pay = 'PAID' AND r.valid AND r.paid) OR (:pay = 'UNPAID' AND r.valid AND NOT r.paid) OR (:pay = 'NOT_ELIGIBLE' AND NOT r.valid))
                   AND (:res::text IS NULL OR r.result = :res)
                   AND (:chk::text IS NULL OR (:chk = 'CHECKED' AND r.checked) OR (:chk = 'NOT_CHECKED' AND NOT r.checked))
                   AND (:from::date IS NULL OR coalesce(r.last_checked_at, r.paid_at) >= (:from::date)::timestamp AT TIME ZONE 'Africa/Lagos')
                   AND (:to::date IS NULL OR coalesce(r.last_checked_at, r.paid_at) < ((:to::date) + 1)::timestamp AT TIME ZONE 'Africa/Lagos')
                """;
        java.util.function.Function<String, JdbcClient.StatementSpec> q = sql -> jdbc.sql(sql)
                .param("s", s).param("fac", blank(faculty), Types.VARCHAR).param("dept", blank(department), Types.VARCHAR).param("prog", blank(programme), Types.VARCHAR)
                .param("sex", sex == null || sex.isBlank() ? null : sex.trim().substring(0, 1).toUpperCase(), Types.VARCHAR)
                .param("pay", upper(payment), Types.VARCHAR).param("res", upper(result), Types.VARCHAR).param("chk", upper(checked), Types.VARCHAR)
                .param("from", from, Types.DATE).param("to", to, Types.DATE);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("session", s);
        out.put("totals", q.apply("""
                SELECT count(*) AS applicants, count(*) FILTER (WHERE r.valid) AS eligible, count(*) FILTER (WHERE r.valid AND r.paid) AS paid,
                       count(*) FILTER (WHERE r.valid AND NOT r.paid) AS unpaid, count(*) FILTER (WHERE r.valid AND r.checked) AS checked,
                       count(*) FILTER (WHERE r.valid AND NOT r.checked) AS not_checked, count(*) FILTER (WHERE r.valid AND r.result = 'ADMITTED') AS admitted,
                       count(*) FILTER (WHERE r.valid AND r.result = 'NOT_ADMITTED') AS not_admitted, count(*) FILTER (WHERE r.valid AND r.result = 'WAITING_LIST') AS waiting,
                       count(*) FILTER (WHERE r.valid AND r.result = 'PENDING') AS pending, coalesce(sum(r.amount) FILTER (WHERE r.paid), 0) AS revenue
                  FROM admissions.status_checking_rows(:s) r""" + where).query().singleRow());
        List<Map<String, Object>> rows = q.apply("""
                SELECT r.application_no, r.jamb_reg_no, r.name, r.sex, r.programme, r.faculty, r.department, r.valid, r.paid, r.paid_at, r.reference, r.amount,
                       r.checked, r.checks, r.first_checked_at, r.last_checked_at, r.last_result, r.result
                  FROM admissions.status_checking_rows(:s) r""" + where + " ORDER BY r.faculty NULLS LAST, r.department NULLS LAST, r.programme, r.name LIMIT 5001").query().listOfRows();
        out.put("truncated", rows.size() > 5000);
        out.put("rows", rows.size() > 5000 ? rows.subList(0, 5000) : rows);
        out.put("faculties", jdbc.sql("SELECT DISTINCT faculty_code AS code, faculty AS name FROM admissions.status_checking_rows(:s) WHERE faculty_code IS NOT NULL ORDER BY 2").param("s", s).query().listOfRows());
        out.put("departments", jdbc.sql("SELECT DISTINCT dept_code AS code, department AS name, faculty_code FROM admissions.status_checking_rows(:s) WHERE dept_code IS NOT NULL ORDER BY 2").param("s", s).query().listOfRows());
        out.put("programmes", jdbc.sql("SELECT DISTINCT programme_code AS code, programme AS name, dept_code FROM admissions.status_checking_rows(:s) WHERE programme_code IS NOT NULL ORDER BY 2").param("s", s).query().listOfRows());
        return out;
    }

    private static String blank(String v) {
        return v == null || v.isBlank() ? null : v.trim();
    }

    private static String upper(String v) {
        return v == null || v.isBlank() ? null : v.trim().toUpperCase();
    }

    /* ── the parts ── */

    private Map<String, Object> state(String type, String session, Integer semester) {
        return jdbc.sql("SELECT * FROM policy.window_state(:t, :s, :sem)").param("t", type).param("s", session).param("sem", semester, Types.INTEGER).query().singleRow();
    }

    private List<Map<String, Object>> history(String session, String type, int limit) {
        return jdbc.sql("""
                SELECT e.id, e.window_type, e.session, e.semester, e.action, e.previous_state, e.new_state, e.previous_opens_at, e.previous_closes_at, e.previous_late_until,
                       e.new_opens_at, e.new_closes_at, e.new_late_until, e.late_fee_enabled, e.reason, e.office, e.at,
                       (SELECT p.surname || ', ' || p.given_names FROM iam.person p WHERE p.id = e.actor) AS officer
                  FROM policy.portal_window_event e
                 WHERE (:s::text IS NULL OR e.session = :s) AND (:t::text IS NULL OR e.window_type = :t)
                 ORDER BY e.at DESC LIMIT :n
                """).param("s", session == null || session.isBlank() ? null : session.trim(), Types.VARCHAR).param("t", type == null || type.isBlank() ? null : type.trim().toUpperCase(), Types.VARCHAR)
                .param("n", limit).query().listOfRows();
    }

    private static String word(String type) {
        return switch (type) {
            case "SCHOOL_FEES_PAYMENT" -> "School fees payment";
            case CHECKING -> "Admission status checking";
            default -> "Course registration";
        };
    }

    private static String day(Object ts) {
        if (ts == null) return null;
        return jdbcDate(ts);
    }

    private static String jdbcDate(Object ts) {
        try {
            OffsetDateTime t = ts instanceof OffsetDateTime o ? o : OffsetDateTime.parse(String.valueOf(ts));
            return t.atZoneSameInstant(java.time.ZoneId.of("Africa/Lagos")).format(java.time.format.DateTimeFormatter.ofPattern("d MMMM yyyy HH:mm"));
        } catch (RuntimeException e) {
            return String.valueOf(ts);
        }
    }

    /** the students of the session told, by email and SMS where the record has them; the count of those reached is returned */
    private int tell(String type, String session, Integer semester, String action, Map<String, Object> after) {
        String state = String.valueOf(after.get("state"));
        String phase = String.valueOf(after.get("phase"));
        String subject = word(type) + " " + session + (semester == null ? "" : " semester " + semester) + ": " + switch (action) {
            case "CLOSE" -> "closed";
            case "EXTEND" -> "extended";
            case "REOPEN" -> "reopened";
            default -> "open";
        };
        String body = switch (action) {
            case "CLOSE" -> word(type) + " for " + session + (semester == null ? "" : ", semester " + semester) + " is closed from now. " + (after.get("reason") == null ? "" : String.valueOf(after.get("reason")) + " ")
                    + ("SCHOOL_FEES_PAYMENT".equals(type) ? "A reference already generated may still be paid and is confirmed as usual; no new reference is generated until the window is reopened." : "No registration is drafted, changed or submitted until the window is reopened.");
            default -> word(type) + " for " + session + (semester == null ? "" : ", semester " + semester) + " is " + (action.equals("EXTEND") ? "extended" : "open") + "."
                    + (after.get("closes_at") == null ? "" : " It closes on " + day(after.get("closes_at")) + ".")
                    + (after.get("late_until") == null ? "" : " Late " + ("SCHOOL_FEES_PAYMENT".equals(type) ? "payment" : "registration") + " runs until " + day(after.get("late_until")) + (Boolean.TRUE.equals(after.get("late_fee_enabled")) ? ", with the late fee the Bursar states" : "") + ".")
                    + ("LATE".equals(phase) ? " You are now in the late period." : "");
        };
        String sms = "MOAUM: " + subject + ". See the portal.";
        return jdbc.sql("""
                SELECT count(*) FROM (
                    SELECT platform.queue_notice('EMAIL', r.email, :subj, :body || E'\\n\\nDirectorate of ICT, Rev. Fr. Moses Orshio Adasu University, Makurdi', 'student', st.id) AS n
                      FROM people.student st CROSS JOIN LATERAL people.student_reach(st.id) r
                     WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                       AND (st.entry_session = :s OR EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = st.id AND cr.session = :s)
                            OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = st.id AND p.session = :s))
                    UNION ALL
                    SELECT platform.queue_notice('SMS', r.phone, :subj, :sms, 'student', st.id)
                      FROM people.student st CROSS JOIN LATERAL people.student_reach(st.id) r
                     WHERE st.status IN ('ADMITTED', 'ACTIVE', 'PROBATION')
                       AND (st.entry_session = :s OR EXISTS (SELECT 1 FROM registration.course_registration cr WHERE cr.student_id = st.id AND cr.session = :s)
                            OR EXISTS (SELECT 1 FROM finance.payment_reference p WHERE p.student_id = st.id AND p.session = :s))) x
                 WHERE x.n IS NOT NULL
                """).param("subj", subject).param("body", body).param("sms", sms).param("s", session).query(Integer.class).single();
    }
}
