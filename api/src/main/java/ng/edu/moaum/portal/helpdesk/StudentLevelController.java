package ng.edu.moaum.portal.helpdesk;

import java.sql.Types;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.UUID;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

import org.springframework.jdbc.core.simple.JdbcClient;
import org.springframework.security.access.prepost.PreAuthorize;
import org.springframework.security.core.Authentication;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import ng.edu.moaum.portal.shared.DomainRuleViolation;
import ng.edu.moaum.portal.studentportal.StudentPortalService;

import static ng.edu.moaum.portal.helpdesk.SupportAccess.LEVEL_DESK;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.blank;
import static ng.edu.moaum.portal.helpdesk.SupportAccess.can;

/**
 * A student's academic level at the ICT Support Desk (V500). The agent reads the student, the level the record holds, the levels
 * the programme has, the level the cohort engine computes, the levels the registrations carry and every earlier change; then
 * progresses the student to the next level or corrects the level to another of the programme's levels, with a reason and, where
 * there is one, the student's ticket. The database refuses what the programme or the student's status does not allow
 * (people.support_set_level). A registration already made for the session is named to the agent first, who goes on knowingly:
 * (V641) a correction carries into the session's course registration and enrolment at the level corrected from — what the
 * examination card, the GST and EPS permit and the receipt print — and a progression leaves them as they are. Each change is on the
 * cohort decision history and the support ledger, and on the ticket's timeline.
 */
@RestController
@RequestMapping("/api/v1/helpdesk/support")
class StudentLevelController {

    private static final tools.jackson.databind.ObjectMapper JSON = new tools.jackson.databind.ObjectMapper();

    /** V628: spilloverYear with action SPILLOVER — 1 (SP1), 2 (SP2), or 0 (the final year again) */
    public record LevelIn(@NotBlank String action, Integer level, Integer expected, @NotBlank @Size(max = 2000) String reason, UUID ticket,
                          Boolean acknowledgeRegistration, Integer spilloverYear) {
    }

    private final JdbcClient jdbc;
    private final SupportAccess support;
    private final StudentPortalService portal;

    StudentLevelController(JdbcClient jdbc, SupportAccess support, StudentPortalService portal) {
        this.jdbc = jdbc;
        this.support = support;
        this.portal = portal;
    }

    /** the student, the level, the programme's levels, the evidence, the history, and what this agent may do */
    @GetMapping("/students/{id}/level")
    @PreAuthorize(LEVEL_DESK)
    @Transactional(readOnly = true)
    Map<String, Object> level(Authentication auth, @PathVariable UUID id) {
        SupportAccess.Access a = support.on(auth, id);
        can(a, "VIEW_STUDENT");
        String session = portal.sessionFor(id);
        int semester = portal.openSemester(id, session);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("student", jdbc.sql("""
                SELECT s.id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS full_name, s.matric_no, s.jamb_reg_no,
                       (SELECT ap.application_no FROM admissions.application ap WHERE ap.candidate_id = s.candidate_id ORDER BY ap.application_no LIMIT 1) AS application_no,
                       f.name AS faculty, d.name AS department, p.name AS programme, pt.label AS programme_type, s.entry_session AS admission_session,
                       s.current_level, s.status, coalesce(s.study_mode, c.study_mode) AS study_mode, coalesce(c.admission_route, s.entry_mode) AS admission_route,
                       s.entry_mode, s.entry_level
                  FROM people.student s
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN ref.department d ON d.code = p.dept_code
                  LEFT JOIN ref.faculty f ON f.code = coalesce(d.faculty_code, p.faculty_code)
                  LEFT JOIN people.student_classification c ON c.student_id = s.id
                  LEFT JOIN finance.programme_type pt ON pt.code = c.programme_type
                 WHERE s.id = :s
                """).param("s", id).query().singleRow());
        out.put("session", session);
        out.put("semester", semester);
        out.put("options", JSON.readValue(jdbc.sql("SELECT people.level_options(:s)::text").param("s", id).query(String.class).single(), Map.class));
        // the cohort engine's reading of where the student should stand (V331, V475): evidence for the agent, not a rule here — with
        // the spillover the agent must see (the year past the programme's length, against the limit the policy allows)
        Map<String, Object> position = jdbc.sql("""
                SELECT ap.computed_level, ap.spillover_state, ap.classification, ap.effective_cohort, ap.expected_completion, ap.graduation_state,
                       ap.final_level, ap.duration_years, ap.spillover_years, ap.elapsed_sessions, ap.last_session,
                       (SELECT g.max_spillover_years FROM policy.progression_setting g LIMIT 1) AS max_spillover
                  FROM people.academic_position ap WHERE ap.student_id = :s
                """).param("s", id).query().listOfRows().stream().findFirst().orElse(null);
        out.put("position", position);
        // the courses still owed — what a spillover student must pass to finish (a published failure not passed since)
        out.put("carryovers", position != null && String.valueOf(position.get("spillover_state")).startsWith("SPILLOVER")
                ? jdbc.sql("SELECT course_code, title, units, failed_in FROM registration.carryovers(:s) ORDER BY course_code").param("s", id).query().listOfRows()
                : java.util.List.of());
        out.put("registrations", jdbc.sql("""
                SELECT r.session, r.semester, r.level, r.status,
                       (SELECT count(*) FROM registration.entry e WHERE e.registration_id = r.id AND e.status NOT IN ('DROPPED', 'WITHDRAWN')) AS courses
                  FROM registration.course_registration r WHERE r.student_id = :s ORDER BY r.session, r.semester
                """).param("s", id).query().listOfRows());
        out.put("history", history(id));
        out.put("mayProgress", a.has("PROGRESS_LEVEL"));
        out.put("mayCorrect", a.has("CORRECT_LEVEL"));
        out.put("scope", a.scope());
        return out;
    }

    /** progress to the next level, or correct the level: with the reason, the ticket where there is one, and — when the student has
     *  registered for the session — the agent's word that they know the registration stays as it is */
    @PostMapping("/students/{id}/level")
    @PreAuthorize(LEVEL_DESK)
    @Transactional
    Map<String, Object> change(Authentication auth, @PathVariable UUID id, @Valid @RequestBody LevelIn body) {
        SupportAccess.Access a = support.on(auth, id);
        String action = body.action().trim().toUpperCase();
        switch (action) {
            case "PROGRESS" -> can(a, "PROGRESS_LEVEL");
            case "CORRECTION", "CORRECT" -> { action = "CORRECTION"; can(a, "CORRECT_LEVEL"); }
            // V628: a spillover year is a correction of where the student stands, by the expected completion it pins
            case "SPILLOVER" -> can(a, "CORRECT_LEVEL");
            default -> throw new DomainRuleViolation("LEVEL_ACTION", "A level is progressed (PROGRESS), corrected (CORRECTION) or set to a spillover year (SPILLOVER).");
        }
        String reason = body.reason().trim();
        UUID ticket = support.ticketFor(a, body.ticket(), id, false);
        String session = portal.sessionFor(id);
        int semester = portal.openSemester(id, session);
        List<Map<String, Object>> registered = jdbc.sql("""
                SELECT r.semester, r.level, r.status FROM registration.course_registration r WHERE r.student_id = :s AND r.session = :ses ORDER BY r.semester
                """).param("s", id).param("ses", session).query().listOfRows();
        if (!registered.isEmpty() && !Boolean.TRUE.equals(body.acknowledgeRegistration())) {
            Map<String, Object> r = registered.get(registered.size() - 1);
            String reg = "This student already has a course registration for " + session + " semester " + r.get("semester")
                    + " (" + String.valueOf(r.get("status")).toLowerCase() + ", " + r.get("level") + " Level). ";
            // V641: a correction carries into the session's registration and enrolment; a progression does not
            throw new DomainRuleViolation("LEVEL_REGISTRATION_ACK", "CORRECTION".equals(action)
                    ? reg + "Correcting the level sets the session's registration and enrolment to the corrected level, so the examination card, the GST & EPS permit and the receipt print it; the courses registered stay as they are."
                    : reg + "Changing the level does not change it; the courses the student may choose follow the new level.",
                    new DomainRuleViolation.Remedy("CORRECTION".equals(action) ? "Confirm that you have seen this." : "Confirm that you have seen this, or correct the level instead if the session's level was wrong.", "You"));
        }
        if ("SPILLOVER".equals(action)) {
            return spillover(auth, id, body, reason, ticket, session, semester, !registered.isEmpty());
        }
        Map<String, Object> done = JSON.readValue(jdbc.sql("SELECT people.support_set_level(:s, :a, :l, :e, :r, :ses, :sem, :t)::text")
                .param("s", id).param("a", action).param("l", body.level(), Types.INTEGER).param("e", body.expected(), Types.INTEGER).param("r", reason)
                .param("ses", session, Types.VARCHAR).param("sem", semester).param("t", ticket, Types.OTHER).query(String.class).single(), Map.class);
        if (!Boolean.TRUE.equals(done.get("alreadyDone"))) {
            String from = String.valueOf(done.get("previousLevel")), to = String.valueOf(done.get("newLevel"));
            boolean progress = "PROGRESS".equals(action);
            support.act(id, ticket, progress ? "LEVEL_PROGRESSED" : "LEVEL_CORRECTED", "current_level", from, to, reason, session, semester,
                    Map.of("summary", "Student academic level " + (progress ? "progressed" : "corrected") + " from " + from + " to " + to,
                           "before", Map.of("current_level", done.get("previousLevel")), "after", Map.of("current_level", done.get("newLevel"))));
        }
        Map<String, Object> out = new LinkedHashMap<>(done);
        // V641: a correction's registration follows it ('carried' says how many rows); a progression's stays
        out.put("registrationKept", !registered.isEmpty() && !"CORRECTION".equals(action));
        out.put("view", level(auth, id));
        return out;
    }

    /**
     * V628: the student set to a spillover year (SP1, SP2) or back to the final year — the record at the programme's final level and the
     * expected completion pinned so the cohort engine counts this session as that year (people.support_set_spillover)
     */
    private Map<String, Object> spillover(Authentication auth, UUID id, LevelIn body, String reason, UUID ticket, String session, int semester,
                                          boolean registered) {
        if (body.spilloverYear() == null) {
            throw new DomainRuleViolation("LEVEL_SPILLOVER_YEAR", "Say which spillover year: SP1, SP2, or the final year again.");
        }
        Map<String, Object> done = JSON.readValue(jdbc.sql("SELECT people.support_set_spillover(:s, :y, :e, :r, :ses, :sem, :t)::text")
                .param("s", id).param("y", body.spilloverYear()).param("e", body.expected(), Types.INTEGER).param("r", reason)
                .param("ses", session, Types.VARCHAR).param("sem", semester).param("t", ticket, Types.OTHER).query(String.class).single(), Map.class);
        if (!Boolean.TRUE.equals(done.get("alreadyDone"))) {
            String from = String.valueOf(done.get("previousLevel")), to = String.valueOf(done.get("newLevel"));
            int year = body.spilloverYear();
            String word = year == 0 ? "the final year" : "SP" + year;
            support.act(id, ticket, "LEVEL_CORRECTED", "current_level", from, to + (year == 0 ? "" : " (SP" + year + ")"), reason, session, semester,
                    Map.of("summary", "Student set to " + word + " at " + to + " Level (expected completion " + done.get("expectedCompletion") + ")",
                           "before", Map.of("current_level", done.get("previousLevel")),
                           "after", Map.of("current_level", done.get("newLevel"), "spillover_year", year, "expected_completion", String.valueOf(done.get("expectedCompletion")))));
        }
        Map<String, Object> out = new LinkedHashMap<>(done);
        out.put("registrationKept", registered);
        out.put("view", level(auth, id));
        return out;
    }

    /** every level change on the record, whoever made it: the ICT Support Desk, the Registry's decisions, the cohort corrections */
    private List<Map<String, Object>> history(UUID id) {
        return jdbc.sql("""
                SELECT d.id, d.decided_at, d.previous_level, d.new_level, d.rule, d.reason, d.actor_office, d.session, d.semester,
                       helpdesk.person_name(d.officer) AS officer, t.number AS ticket_number, d.batch_ref
                  FROM people.cohort_decision d LEFT JOIN helpdesk.ticket t ON t.id = d.ticket_id
                 WHERE d.student_id = :s AND d.new_level IS NOT NULL AND (d.previous_level IS DISTINCT FROM d.new_level OR d.rule = 'LEVEL_SPILLOVER_YEAR')
                 ORDER BY d.decided_at DESC LIMIT 100
                """).param("s", id).query().listOfRows();
    }

    /** Level Change History: every level change within the reader's reach, filtered, paged, and the whole of it for an export */
    @GetMapping("/levels/history")
    @PreAuthorize(LEVEL_DESK)
    @Transactional(readOnly = true)
    Map<String, Object> changes(Authentication auth, @RequestParam(required = false) String action, @RequestParam(required = false) String q,
                                @RequestParam(required = false) java.time.LocalDate from, @RequestParam(required = false) java.time.LocalDate to,
                                @RequestParam(defaultValue = "1") int page, @RequestParam(defaultValue = "50") int size, @RequestParam(defaultValue = "false") boolean export) {
        SupportAccess.Access a = support.access(auth);
        String cap = a.has("VIEW_SUPPORT_AUDIT") ? "VIEW_SUPPORT_AUDIT" : "VIEW_LEVEL_HISTORY";
        can(a, cap);
        int sz = Math.max(1, Math.min(size, export ? 5000 : 200));
        int pg = Math.max(1, page);
        String act = blank(action) == null ? null : action.trim().toUpperCase();
        String like = blank(q) == null ? null : "%" + q.trim().toUpperCase().replace("\\", "\\\\").replace("%", "\\%").replace("_", "\\_") + "%";
        String where = """
                  FROM people.cohort_decision d
                  JOIN people.student s ON s.id = d.student_id
                  LEFT JOIN ref.programme p ON p.code = s.programme_code
                  LEFT JOIN helpdesk.ticket t ON t.id = d.ticket_id
                 WHERE d.new_level IS NOT NULL AND (d.previous_level IS DISTINCT FROM d.new_level OR d.rule = 'LEVEL_SPILLOVER_YEAR')
                   AND (:head OR EXISTS (SELECT 1 FROM sc WHERE sc.global OR p.faculty_code = ANY (sc.faculties) OR p.dept_code = ANY (sc.departments)))
                   AND (:act::text IS NULL OR (:act = 'SUPPORT' AND d.rule IN ('LEVEL_PROGRESS', 'LEVEL_CORRECTION', 'LEVEL_SPILLOVER_YEAR'))
                        OR (:act = 'OTHER' AND d.rule NOT IN ('LEVEL_PROGRESS', 'LEVEL_CORRECTION', 'LEVEL_SPILLOVER_YEAR')) OR d.rule = :act)
                   AND (:like::text IS NULL OR upper(coalesce(s.matric_no, '')) LIKE :like ESCAPE '\\' OR upper(s.surname || ' ' || s.other_names) LIKE :like ESCAPE '\\'
                        OR upper(coalesce(t.number, '')) LIKE :like ESCAPE '\\')
                   AND (:from::date IS NULL OR d.decided_at >= :from)
                   AND (:to::date IS NULL OR d.decided_at < :to + 1)
                """;
        String cte = "WITH sc AS MATERIALIZED (SELECT * FROM helpdesk.agent_scope_for(:me, :cap)) ";
        java.util.function.Function<String, JdbcClient.StatementSpec> with = sql -> jdbc.sql(sql)
                .param("head", a.head()).param("me", a.agent()).param("cap", cap).param("act", act, Types.VARCHAR).param("like", like, Types.VARCHAR)
                .param("from", from, Types.DATE).param("to", to, Types.DATE);
        Map<String, Object> out = new LinkedHashMap<>();
        out.put("total", with.apply(cte + "SELECT count(*) " + where).query(Long.class).single());
        out.put("rows", with.apply(cte + """
                SELECT d.id, d.decided_at, s.id AS student_id, upper(btrim(s.surname)) || coalesce(', ' || nullif(btrim(s.other_names), ''), '') AS student,
                       coalesce(s.matric_no, s.admission_no) AS number, p.name AS programme, d.previous_level, d.new_level, d.rule, d.reason,
                       helpdesk.person_name(d.officer) AS changed_by, d.actor_office, t.number AS ticket_number, d.session, d.semester
                """ + where + " ORDER BY d.decided_at DESC, d.id LIMIT :n OFFSET :off").param("n", sz).param("off", (long) (pg - 1) * sz).query().listOfRows());
        out.put("page", pg);
        out.put("size", sz);
        out.put("scope", a.scope());
        return out;
    }
}
