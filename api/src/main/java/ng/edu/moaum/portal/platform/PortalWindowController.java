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
 */
@RestController
@RequestMapping("/api/v1/portal-windows")
class PortalWindowController {

    /** the one office that opens and closes the portal's windows */
    private static final String DIRECTOR = "hasAuthority('OFFICE_ict')";
    private static final List<String> TYPES = List.of("SCHOOL_FEES_PAYMENT", "COURSE_REGISTRATION");

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
        if (!TYPES.contains(t)) {
            throw new DomainRuleViolation("WINDOW_TYPE", "The portal's windows are school fees payment and course registration.", new DomainRuleViolation.Remedy("Name one of the two.", "Directorate of ICT"));
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
            told = tell(t, body.session().trim(), body.semester(), body.action(), after);
        }
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("windowId", id);
        out.put("before", before);
        out.put("after", after);
        out.put("told", told);
        out.putAll(read(body.session()));
        return out;
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
        return "SCHOOL_FEES_PAYMENT".equals(type) ? "School fees payment" : "Course registration";
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
